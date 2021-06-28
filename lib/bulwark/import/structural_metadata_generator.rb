# frozen_string_literal: true
module Bulwark
  class Import
    class StructuralMetadataGenerator
      attr_reader :filenames, :bibnumber, :drive, :path, :viewing_direction, :display, :sequence, :errors

      def initialize(options = {})
        options = options.deep_symbolize_keys

        @filenames         = options[:filenames]
        @bibnumber         = options[:bibnumber]
        @drive             = options[:drive]
        @path              = options[:path]
        @viewing_direction = options[:viewing_direction]
        @display           = options[:display]

        # Files ordered in sequence, can only be used in conjunction with viewing_direction and display
        @sequence          = options[:sequence].blank? ? nil : options[:sequence].map(&:deep_symbolize_keys)

        @errors            = []
      end

      # Check that options are valid for generating a structural metadata csv. In order for a structural
      # metadata csv to be created one of the following options should be provided: a list of filenames,
      # a bibnumber or a file location.
      def valid?
        @errors << 'structural drive and path must both be provided' if (drive && !path) || (path && !drive)
        @errors << 'structural viewing_direction cannot be provided without filenames or sequence' if viewing_direction && (!filenames && !sequence)
        @errors << 'structural display cannot be provided without filenames or sequence' if display && (!filenames && !sequence)
        @errors << 'structural drive invalid' if drive && !MountedDrives.valid?(drive)
        @errors << 'structural metadata cannot be provided multiple ways' unless [filenames, (drive || path), bibnumber, sequence].one?
        @errors << 'structural viewing direction is not valid' if viewing_direction && !MetadataSource::VIEWING_DIRECTIONS.include?(viewing_direction)
        @errors << 'structural display is not valid' if display && !MetadataSource::VIEWING_HINTS.include?(display)
        @errors << 'structural sequence must contain filename for every file in sequence' if sequence&.any? { |h| h[:filename].blank? }

        # @errors << "structural path invalid" if drive && path && !MountedDrives.valid_path?(drive, path)

        errors.empty?
      end

      # Generates structural metadata csv based on the options given.
      #
      # @param [Hash] options options used to generate structural metadata csv
      # @option options [Array<String>] :filenames list of ordered filenames
      # @option options [String] :drive to be used in conjunction with :path to retrieve file
      # @option options [String] :path to be used in conjunction with :drive to retrieve file
      # @option options [String] :bibnumber id used to retrieve structural metadata from Marmite (external service)
      def csv
        raise ArgumentError, 'options not valid' unless valid?

        if filenames
          from_ordered_filenames(filenames, display, viewing_direction)
        elsif sequence
          from_sequence(sequence, display, viewing_direction)
        elsif drive && path
          filepath = File.join(MountedDrives.path_to(drive), path)
          from_file(filepath)
        elsif bibnumber
          from_bibnumber(bibnumber)
        end
      end

      private

        # Generating structural metadata csv from ordered filenames.
        #
        # @param [Array<String>] filenames in order
        def from_ordered_filenames(filenames, display = nil, viewing_direction = nil)
          CSV.generate do |csv|
            headers = ['filename', 'sequence']
            headers << 'display' if display
            headers << 'viewing_direction' if viewing_direction

            csv << headers
            filenames.split(';').map(&:strip).each_with_index do |f, i|
              csv << [f, i + 1, display, viewing_direction].compact
            end
          end
        end

        # Generating structural metadata from sequenced filename with advanced structural metadata.
        #
        # @param [Array<Hash>] ordered file information
        def from_sequence(sequence, display = nil, viewing_direction = nil)
          sequence.each_with_index do |f, i|
            f[:sequence] = i + 1
            f[:viewing_direction] = viewing_direction if viewing_direction
            f[:display] = display if display
          end

          Bulwark::StructuredCSV.generate(sequence)
        end

        # Reading in structural metadata csv from filesystem.
        #
        # @param [String] path to metadata
        def from_file(filepath)
          raise 'structural metadata path must lead to a file.' unless File.file?(filepath)
          File.read(filepath)
        end

        # Generates structural metadata csv from structural and descriptive metadata found in Marmite.
        #
        # Note: Once we load all the items that require structural metadata from Marmite, we will no longer
        # have a need for this ability.
        def from_bibnumber(bibnumber)
          # Retrieve descriptive metadata from Marmite in order to retrieve viewing direction.
          marc_996_a = Nokogiri::XML(MarmiteClient.marc21(bibnumber))
                               .xpath('/marc:records/marc:record/marc:datafield[@tag="996"]/marc:subfield[@code="a"]')
                               .map(&:text).first

          viewing_direction = convert_to_viewing_direction(marc_996_a)

          # If value is set to `unbound` viewing hint should be set to `individuals` otherwise we can assume the item should be `paged`.
          display = marc_996_a == 'unbound' ? MetadataSource::INDIVIDUALS : MetadataSource::PAGED

          # Retrieving metadata from Marmite via bibnumber.
          structural_data = Nokogiri::XML(MarmiteClient.structural(bibnumber)).xpath('//record/pages/page').map do |page|
            {
              'label' => page['visiblepage'],
              'sequence' => page['seq'],
              'filename' => "#{page['image']}.tif",
              'viewing_direction' => viewing_direction,
              'display' => display,
              'table_of_contents' => page.xpath('tocentry').map(&:text)
            }
          end

          StructuredCSV.generate(structural_data)
        end

        # Converts value in MARC 996 field to viewing_direction
        def convert_to_viewing_direction(value)
          case value
          when 'hinge-right'
            MetadataSource::RIGHT_TO_LEFT
          when 'hinge-top'
            MetadataSource::TOP_TO_BOTTOM
          when 'hinge-bottom'
            MetadataSource::BOTTOM_TO_TOP
          else
            MetadataSource::LEFT_TO_RIGHT
          end
        end
    end
  end
end
