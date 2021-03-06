require 'open-uri'
require 'csv_xlsx_converter'

class MetadataSource < ActiveRecord::Base
  include Utils::Artifacts::InputFormats
  include DescriptiveMetadataSources
  include StructuralMetadataSources

  STRUCTURAL_TYPES = %w[custom structural_bibid pap_structural kaplan_structural pqc_ark pqc_combined_struct pqc_structural structural]
  DESCRIPTIVE_TYPES = %w[kaplan pap pqc_combined_desc pqc_desc voyager pqc descriptive]

  attr_accessor :xml_header, :xml_footer
  attr_accessor :user_defined_mappings

  belongs_to :metadata_builder, :foreign_key => 'metadata_builder_id'

  include CustomEncodings

  validates :user_defined_mappings, :xml_tags => true

  serialize :original_mappings, Hash
  serialize :user_defined_mappings, Hash
  serialize :children, Array

  $xml_header = '<?xml version="1.0" encoding="UTF-8"?><root>'
  $xml_footer = '</root>'

  $jettison_files = Set.new

  def path
    read_attribute(:path) || ''
  end

  def num_objects
    read_attribute(:num_objects) || ''
  end

  def x_start
    read_attribute(:x_start) || ''
  end

  def y_start
    read_attribute(:y_start) || ''
  end

  def x_stop
    read_attribute(:x_stop) || ''
  end

  def y_stop
    read_attribute(:y_stop) || ''
  end

  def root_element
    read_attribute(:root_element) || ''
  end

  def parent_element
    read_attribute(:parent_element) || ''
  end

  def children
    read_attribute(:children) || ''
  end

  def original_mappings
    read_attribute(:original_mappings) || ''
  end

  def user_defined_mappings
    read_attribute(:user_defined_mappings) || ''
  end

  def source_type
    read_attribute(:source_type) || ''
  end

  def file_field
    read_attribute(:file_field) || ''
  end

  def view_type
    read_attribute(:view_type) || ''
  end

  def children=(children)
    self[:children] = children.reject(&:blank?)
  end

  def source_type=(source_type)
    self[:source_type] = source_type
    self[:user_defined_mappings] = nil
    self[:original_mappings] = nil
    self.update_last_used_settings
    self.metadata_builder.repo.update_steps(:metadata_source_type_specified) if self.metadata_builder.present?
  end

  def view_type=(view_type)
    self[:view_type] = view_type
    self.metadata_builder.repo.update_steps(:metadata_source_additional_info_set)
  end

  def original_mappings=(original_mappings)
    self[:original_mappings] = original_mappings
    self[:input_source] = input_source_path(self[:source_type])
  end

  def user_defined_mappings=(user_defined_mappings)
    self[:user_defined_mappings] = user_defined_mappings
    self.metadata_builder.repo.update_steps(:metadata_mappings_generated) if user_defined_mappings.present?
  end

  def check_parentage
    sibling_ids = MetadataSource.where('metadata_builder_id = ? AND id != ?', self.metadata_builder, self.id).pluck(:id)
    sibling_ids.each do |sid|
      return MetadataSource.find(sid).children.any?{|child| child == "#{self.id}"} ? sid : nil
    end
  end

  def check_siblings
    sibling_ids = MetadataSource.where('metadata_builder_id = ? AND id != ?', self.metadata_builder, self.id).pluck(:id)
    sibling_ids.each do |sid|
      return MetadataSource.find(sid).children.any?{|child| child == "#{self.id}"} ? sid : nil
    end
  end

  def input_source_path(source_type)
    case source_type
      when 'custom'
        self.path
    when 'voyager'
      reconcile_metadata_lookup_source(source_type, self.original_mappings['bibid'])
    when 'structural_bibid'
      reconcile_metadata_lookup_source(source_type, self.original_mappings['bibid'])
    else
      nil
    end
  end

  def set_metadata_mappings(working_path = '')
    if self.source_type.present?
      case self.source_type
        when 'descriptive'
          descriptive_metadata(working_path)
        when 'structural'
          structural_metadata(working_path)
        when 'custom'
          unless self.root_element.present?
            self.root_element = 'pages'
            self.parent_element = 'page'
          end
          self.original_mappings = _convert_metadata(working_path)
          self.identifier = self.path.filename_sanitize
        when 'structural_bibid'
          self.root_element = 'pages'
          self.parent_element = 'page'
          self.file_field = 'file_name'
          self.user_defined_mappings = _set_marmite_structural_metadata(working_path)
          self.identifier = self.original_mappings['bibid']
        when 'voyager'
          self.root_element = MetadataSchema.config[:voyager][:root_element] || 'record'
          self.user_defined_mappings = _set_marmite_data(working_path)
          self.identifier = self.original_mappings['bibid']
        when 'kaplan'
          self.set_kaplan_data(working_path)
        when 'pap'
          self.root_element = MetadataSchema.config[:voyager][:root_element] || 'record'
          self.user_defined_mappings = _set_marmite_data(working_path)
          self.identifier = self.original_mappings['bibid']
        when 'pap_structural'
          self.root_element = 'pages'
          self.parent_element = 'page'
          self.file_field = 'file_name'
          self.user_defined_mappings = _set_marmite_structural_metadata(working_path)
          self.identifier = self.original_mappings['bibid']
        when 'pqc_ark'
          self.metadata_builder.repo.update_ark_struct_metadata
      when 'pqc_desc'
          self.root_element = MetadataSchema.config[:voyager][:root_element] || 'record'
          self.user_defined_mappings = _set_marmite_data(working_path)
          self.identifier = self.original_mappings['bibid']
        when 'pqc'
          self.root_element = 'record'
          self.user_defined_mappings = set_pqc_descriptive(working_path)
        when 'pqc_structural'
          self.root_element = 'pages'
          self.parent_element = 'page'
          self.file_field = 'file_name'
          self.set_pqc_struct_md(working_path)
          self.identifier = self.original_mappings['bibid']
        when 'pqc_combined_desc', 'pqc_combined_struct'
          self.user_defined_mappings = _set_marmite_combined_metadata(working_path, self.source_type)
        end
    end

    self.metadata_builder.repo.update_steps(:metadata_extracted)
    self.save!
  end

  def save_input_source(destination_path)
    temp_location, filename = self.fetch_input_artifact('Xml')
    destination = "#{destination_path}/#{Utils.config[:object_admin_path]}/#{filename}"
    FileUtils.mv(temp_location, destination)
  end

  def build_xml
    working_path = self.metadata_builder.repo.version_control_agent.clone
    generate_all_xml(working_path)
    self.metadata_builder.repo.version_control_agent.delete_clone(working_path)
  end

  # Main method that generates xml?
  def generate_all_xml(working_path)
    self.generate_and_build_individual_xml(working_path)
    self.children.each do |child|
      begin
        source = MetadataSource.find(child)
      rescue
        source = MetadataSource.find(child.id)
      end
      source.generate_and_build_individual_xml(working_path, source.path) unless %w[kaplan_structural].include?(source.source_type)
    end
    self.generate_preservation_xml(working_path)
    self.generate_pqc_xml(working_path)
    self.jettison_metadata(working_path, $jettison_files) if $jettison_files.present?
    content = "#{working_path}/#{self.metadata_builder.repo.metadata_subdirectory}"
    self.metadata_builder.repo.version_control_agent.add({:content => content}, working_path)
    self.metadata_builder.repo.version_control_agent.commit(I18n.t('colenda.version_control_agents.commit_messages.write_preservation_xml'), working_path)
    self.metadata_builder.repo.version_control_agent.push({:content => content}, working_path)
  end

  def generate_pqc_xml(working_path)
    file_name = "#{working_path}/#{self.metadata_builder.repo.metadata_subdirectory}/#{self.metadata_builder.repo.preservation_filename}"

    mets_relative_path = File.join(self.metadata_builder.repo.metadata_subdirectory, Utils.config['mets_xml_derivative'])

    # Retrieve METS file, if its present
    if ExtendedGit.open(working_path).annex.whereis.includes_file?(mets_relative_path)
      self.metadata_builder.repo.version_control_agent.get({ location: mets_relative_path }, working_path)
      self.metadata_builder.repo.version_control_agent.unlock({ content: mets_relative_path }, working_path)
    end

    doc = Nokogiri::XML(File.read(file_name))
    xslt = Nokogiri::XSLT(File.read("#{Rails.root}/lib/tasks/pqc_mets.xslt"))
    output = xslt.transform(doc)
    pqc_path = File.join(working_path, mets_relative_path)
    File.write(pqc_path, output)
  end

  def jettison_metadata(working_path, files_to_jettison)
    files_to_jettison.each do |f|
      f = _reconcile_working_path_slashes(working_path, f)
      self.metadata_builder.repo.version_control_agent.unlock({:content => f}, working_path)
      self.metadata_builder.repo.version_control_agent.drop({:drop_location => f}, working_path) && `rm -rf #{Shellwords.escape(f)}`
    end
    $jettison_files = Set.new
  end

  # Generates preservation.xml file.
  def generate_and_build_individual_xml(working_path, fname = self.path)
    fname = self.source_type if %w[pqc_desc pqc_ark pqc_combined_desc pqc_combined_struct pqc_structural].include?(self.source_type)
    xml_fname = "#{fname}.xml"
    if self.user_defined_mappings.present? && self.root_element.present?
      case self.source_type
      when 'custom'
          @xml_content_final_copy = xml_from_custom(working_path, fname)
      when 'voyager', 'pap', 'pqc_desc'
          @xml_content_final_copy = xml_from_voyager
      when 'structural_bibid', 'pap_structural', 'pqc_ark', 'pqc_combined_struct'
          @xml_content_final_copy = xml_from_structural_bibid
      when 'kaplan', 'pqc', 'pqc_structural'
          @xml_content_final_copy = xml_from_flat_mappings
      else
        return
      end
      $jettison_files.add(xml_fname)
      xml_fname = "#{self.metadata_builder.repo.metadata_subdirectory}/#{self.metadata_builder.repo.preservation_filename}" if self.source_type == 'pqc'  # TODO: refactor for structural
      _fetch_write_save_preservation_xml(working_path, xml_fname, @xml_content_final_copy)
    end
  end

  def generate_preservation_xml(working_path)
    if (self.children.present? || (parent_id = check_parentage).present?) && self.source_type != 'kaplan' && self.source_type != 'pqc_structural'
      @xml_content_final = parent_id.present? ? MetadataSource.find(parent_id).generate_parent_child_xml(working_path) : self.generate_parent_child_xml(working_path)
    elsif self.source_type == 'pqc'
      file = File.new(_reconcile_working_path_slashes(working_path, "#{self.metadata_builder.repo.metadata_subdirectory}/#{self.metadata_builder.repo.preservation_filename}"))
      @xml_content_final = file.readline
    else
      xml_fname = %w[pqc_desc pqc_ark pqc_combined_desc pqc_combined_struct pqc_structural].include?(self.source_type) ? "#{self.source_type}" : "#{self.path}.xml"
      xml_fname = xml_fname.ends_with?('.xml') ? xml_fname : "#{xml_fname}.xml"
      file = File.new(_reconcile_working_path_slashes(working_path, xml_fname))
      @xml_content_final = file.readline
    end
    _fetch_write_save_preservation_xml(working_path, @xml_content_final)
    self.metadata_builder.repo.update_steps(:preservation_xml_generated)
  end

  def xml_from_voyager
    @xml_content = ''
    self.user_defined_mappings.each do |mapping|
      tag = mapping.first
      mapped_values_array = mapping.last.try(:each) || Array[*mapping.last.lstrip]
      mapped_values_array.each do |mapped_val|
        @xml_content << "<#{tag.valid_xml_tag}>#{mapped_val.valid_xml_text}</#{tag.valid_xml_tag}>"
      end
    end
    @xml_content_transformed = "<#{self.root_element}>#{@xml_content}</#{self.root_element}>"
  end

  def xml_from_custom(working_path, fname)
    inner_content = ''
    if self.children.present?
      self.user_defined_mappings.each do |mapping|
        tag = mapping.last['mapped_value']
        self.original_mappings[mapping.first].each do |field_value|
          inner_content << "<#{tag.valid_xml_tag}>#{field_value.valid_xml_text}</#{tag.valid_xml_tag}>"
        end
      end
    else
      self.metadata_builder.repo.version_control_agent.get({:location => "#{working_path}/#{fname}"}, working_path)
      inner_content << _child_values("#{working_path}/#{fname}")
    end
    if self.root_element.present?
      wrapped_content = "<#{root_element.valid_xml_tag}>#{inner_content}</#{root_element.valid_xml_tag}>"
    else
      wrapped_content = "#{inner_content}"
    end
    wrapped_content
  end

  def xml_from_structural_bibid
    inner_content = ''
    if self.children.present?
      self.user_defined_mappings.each do |mapping|
        tag = mapping.last['mapped_value']
        self.original_mappings[mapping.first].each do |field_value|
          inner_content << "<#{tag}>#{field_value}</#{tag}>"
        end
      end
    else
      self.num_objects = self.user_defined_mappings.size
      self.save!

      inner_content << _child_values_voyager
    end
    if self.root_element.present?
      wrapped_content = "<#{root_element.valid_xml_tag}>#{inner_content}</#{root_element.valid_xml_tag}>"
    else
      wrapped_content = "#{inner_content}"
    end
    wrapped_content
  end

  def xml_from_flat_mappings
    parent_content = ''
    child_content = ''
    xml_content = ''

    # To circumvent bug in assuming implicit ordering of metadata sources for all descriptive to come before structural
    m = self.metadata_builder.metadata_source.sort { |a,b| b.children.length <=> a.children.length }.first

    m.user_defined_mappings.each do |mapping|
      tag = mapping.first.valid_xml_tag
      mapping.last.each do |value|
        parent_content << "<#{tag}>#{value.to_s.valid_xml_text}</#{tag}>"
      end
      xml_content = "<#{self.root_element}>#{parent_content}</#{self.root_element}>"
    end
    if m.children.present?
      structural = MetadataSource.find(m.children.first)
      structural.user_defined_mappings.each do |mapping|
        child_content << "<#{structural.parent_element}>"
        mapping.last.each do |key, value|
          child_content << "<#{key.valid_xml_tag}>#{value.to_s.valid_xml_text}</#{key.valid_xml_tag}>"
        end
        child_content << "</#{structural.parent_element}>"
      end
      xml_content = "<#{m.root_element}>#{parent_content}<#{structural.root_element}>#{child_content}</#{structural.root_element}></#{m.root_element}>"
    end
    return xml_content
  end

  def generate_parent_child_xml(working_path)
    content = ''
    key_path = %w[pqc_desc pqc_ark pqc_combined_desc pqc_combined_ark].include?(self.source_type) ? _reconcile_working_path_slashes(working_path, "#{self.source_type}.xml") : _reconcile_working_path_slashes(working_path, "#{self.path}.xml")
    self.generate_and_build_individual_xml(working_path)
    self.children.each do |child|
      child_path = MetadataSource.where(:id => child).pluck(:path).first
      child = child.is_a?(String) ? MetadataSource.find(child) : child
      child_content_path = %w[pqc_desc pqc_ark pqc_combined_desc pqc_combined_struct pqc_structural].include?(child.source_type) ? _reconcile_working_path_slashes(working_path, "#{child.source_type}.xml") : _reconcile_working_path_slashes(working_path, "#{child_path}.xml")
      self.metadata_builder.repo.version_control_agent.get({:location => key_path}, working_path)
      self.metadata_builder.repo.version_control_agent.get({:location => child_content_path}, working_path)
      content = File.open(key_path, 'r'){|io| io.read}
      unless self.source_type == 'pqc_combined_desc'
        child_inner_content = File.open(child_content_path, 'r'){|io| io.read}
        _strip_headers(content) && _strip_headers(child_inner_content)
        end_tag = "</#{self.root_element}>"
        insert_index = content.index(end_tag)
        content.insert(insert_index, child_inner_content)
      end
    end
    content
  end

  def generate_review_status_xml
    review_status_xml = ''
    self.metadata_builder.repo.review_status.each do |review_status|
      review_status_xml << "<#{I18n.t('colenda.metadata_sources.xml.review_tag')}>#{review_status}</#{I18n.t('colenda.metadata_sources.xml.review_tag')}>"
    end
    review_status_xml
  end

  def parse_error_messages(error_messages)
    parsed = '<ul>'
    error_messages.flatten.each do |message|
      parsed << "<li>#{message}</li>"
    end
    parsed << '</ul>'
    parsed
  end

  def update_last_used_settings
    self.last_settings_updated = DateTime.now
    self.save!
  end

  def set_kaplan_data(working_path)
    self.root_element = 'record'
    self.view_type = 'horizontal'
    self.y_start = 1
    self.y_stop = 1
    self.x_start = 1
    self.x_stop = 34
    structural = self.metadata_builder.metadata_source.any? {|a| a.source_type == 'kaplan_structural'} ? MetadataSource.find(self.children.first) : initialize_kaplan_structural(self)
    sanitized = "#{working_path}/" unless working_path.ends_with?('/')
    full_path = "#{sanitized}#{self.path}"
    self.metadata_builder.repo.version_control_agent.get({:location => full_path}, working_path)
    update_source_path(full_path, 'kaplan') if full_path.ends_with?('csv')
    self.generate_kaplan_descrip_md(full_path)
    self.save!
    structural.generate_kaplan_struct_md(xml_sanitized(self.original_mappings))
    structural.save!
  end

  # Basically the same as the Kaplan workflow -- use from now on for PQC-compliant objects
  def set_pqc_descriptive(working_path)
    self.root_element = 'record'
    self.view_type = 'horizontal'
    self.y_start = 1
    self.y_stop = 1
    self.x_start = 1
    self.x_stop = 34
    sanitized = "#{working_path}/" unless working_path.ends_with?('/')
    full_path = "#{sanitized}#{self.path}"
    self.metadata_builder.repo.version_control_agent.get({:location => full_path}, working_path)
    mappings = {}
    headers = []
    x_start, y_start, x_stop, y_stop, z = _offset
    workbook = RubyXL::Parser.parse(full_path)
    workbook[z][y_start].cells.each do |c|
      headers << c.value
    end
    (x_start..x_stop).each_with_index do |i, index|
      val = (workbook[z][y_start+1][x_start+index].present? && workbook[z][y_start+1][x_start+index].value.present?) ? workbook[z][y_start+1][x_start+index].value : ''
      header = headers[i]
      mappings[header] = [] if mappings[header].nil?
      split_multivalued(val).each { |v| mappings[header] << v if v.present? }
    end

    self.original_mappings = mappings
    mappings = xml_sanitized(mappings)
    mappings = crosswalk_to_pqc(mappings, self.source_type)
    mappings
  end

  def set_pqc_struct_md(working_path)
    self.y_start = 1
    self.y_stop = 1
    self.x_start = 1
    self.x_stop = 6
    sanitized = "#{working_path}/" unless working_path.ends_with?('/')
    full_path = "#{sanitized}#{self.path}"
    self.metadata_builder.repo.version_control_agent.get({:location => full_path}, working_path)
    mappings = {}
    headers = []
    x_start, y_start, x_stop, y_stop, z = _offset
    workbook = RubyXL::Parser.parse(full_path)
    workbook[z][y_start].cells.each do |c|
      headers << c.value
    end
    headers.reject!(&:blank?)
    multirow = ["PAGE SEQUENCE", "VISIBLE PAGE", "TOC ENTRY", "FILENAME", "NOTES"]
      workbook.worksheets[z].drop(1).each_with_index do |row, index|
        next if row.cells.all?{|x| x.nil? == true || x.value.nil? == true}
        page_hash = {}
        multirow.each do |row_m|
          row_key = row_m == "FILENAME" ? 'file_name' : row_m.downcase.gsub(" ","_")
          page_hash[row_key] = (row[headers.find_index(row_m)].nil? || row[headers.find_index(row_m)].value.nil?) ? {} : row[headers.find_index(row_m)].value
        end
        mappings[index] = page_hash
      end
    self.original_mappings = mappings
    self.user_defined_mappings = mappings
  end

  # Only gets called if the metadata source file is a CSV
  def update_source_path(source_path, source_type = '')
    case source_type
      when 'kaplan'
        source_path = csv_to_xlsx(source_path)
        self.metadata_builder.repo.version_control_agent.add(:content => source_path)
        self.metadata_builder.repo.version_control_agent.commit(I18n.t('colenda.version_control_agents.commit_messages.write_xlsx_from_csv'))
        self.metadata_builder.repo.version_control_agent.push
        self.path = "/#{self.metadata_builder.repo.metadata_subdirectory}/#{File.basename(source_path)}"
        self.save!
      else
        return
    end
  end

  def generate_kaplan_descrip_md(full_path)
    mappings = {}
    headers = []
    x_start, y_start, x_stop, y_stop, z = _offset
    workbook = RubyXL::Parser.parse(full_path)
    workbook[z][y_start].cells.each do |c|
      if c.present?
        headers << c.value
      else
        headers << "Blank"
      end
    end
    (x_start..x_stop).each_with_index do |i, index|
      val = (workbook[z][y_start+1][x_start+index].present? && workbook[z][y_start+1][x_start+index].value.present?) ? workbook[z][y_start+1][x_start+index].value : ''
      header = headers[i]
      mappings[header] = [] if mappings[header].nil?
      split_multivalued(val).each { |v| mappings[header] << v if v.present? }
    end

    self.original_mappings = mappings
    mappings['collection'] = 'Arnold and Deanne Kaplan Collection of Americana'
    mappings = xml_sanitized(mappings)
    mappings = crosswalk_to_pqc(mappings, self.source_type)
    self.user_defined_mappings = mappings
  end

  # Not used.
  def determine_format_type(source_mapping)
    return nil unless source_mapping.present?
    source_mapping = [source_mapping] unless source_mapping.respond_to?(:each)
    ColendaBase.af_models.each do |model|
      return [model] if source_mapping.any?{|a| a.include?(model)}
    end
    return []
  end

  def crosswalk_to_pqc(mappings, source_type)
    pqc_mappings = {}
    case source_type
      when 'kaplan'
        mappings.each do |key, value|
          crosswalked_term = MetadataSourceCrosswalks::Kaplan.mapping(key)
          mappings.delete(key) && next if crosswalked_term.nil?
          pqc_mappings[crosswalked_term] = [] if pqc_mappings[crosswalked_term].nil?
          if value.present?
            if value.respond_to?(:each)
              value.reject(&:empty?).each do |v|
                pqc_mappings[crosswalked_term] << v
              end
            else
              pqc_mappings[crosswalked_term] << value
            end
          end
        end
      when 'pqc'
        mappings.each do |key, value|
          crosswalked_term = MetadataSourceCrosswalks::Pqc.mapping(key)
          mappings.delete(key) && next if crosswalked_term.nil?
          pqc_mappings[crosswalked_term] = [] if pqc_mappings[crosswalked_term].nil?
          if value.present?
            if value.respond_to?(:each)
              value.reject(&:empty?).each do |v|
                pqc_mappings[crosswalked_term] << v
              end
            else
              pqc_mappings[crosswalked_term] << value
            end
          end
        end
      else
        return  mappings
    end
    return pqc_mappings
  end

  def split_multivalued(value)
    return "#{value}".split('|').map(&:strip)
  end

  def xml_sanitized(mappings)
    sanitized = Hash.new{|k, v| k[v] = []}
    mappings.each do |key, value|
      value = [value] unless value.respond_to?(:each)
      value.reject(&:empty?).each do |v|
        sanitized[key.to_s.valid_xml_tag] << v.to_s.valid_xml_text
      end
    end
    return sanitized
  end

  def generate_kaplan_struct_md(mappings)
    return {} unless mappings['filenames'].present?
    structural_mappings = {}
    file_names = mappings['filenames'].first.split(';').uniq.each{|x| x.gsub!(/[^[:ascii:]]/, ''); x.strip!}
    file_names.each_with_index do |file, i|
      side = ''
      if File.basename(file, ".*").ends_with?('r')
        side = 'recto'
      elsif File.basename(file, ".*").ends_with?('v')
        side = 'verso'
      end
      structural_mappings[i] = {
          'sequence' => i+1,
          'page_number' => i+1,
          'reading_direction' => 'left-to-right',
          'side' => side,
          'file_name' => file,
          'item_type' => mappings['genre']
      }
    end
    self.original_mappings = structural_mappings
    self.user_defined_mappings = structural_mappings
  end

  def initialize_kaplan_structural(parent)

    struct = MetadataSource.create({
                                       :metadata_builder => self.metadata_builder,
                                       :source_type => 'kaplan_structural',
                                       :root_element => 'pages',
                                       :parent_element => 'page',
                                       :view_type => 'horizontal',
                                       :path => "#{parent.path} Structural",
                                       :file_field => 'file_name'
                                   })
    parent.children << struct
    parent.save!
    struct
  end

  def true_root_element(metadata_source)
    parent_id = metadata_source.check_parentage
    parent_id.present? ? MetadataSource.find(parent_id).root_element : metadata_source.root_element
  end

  def thumbnail
    case self.source_type
      when 'custom'
        self.original_mappings['file_name'].present? ? self.original_mappings['file_name'].first : nil
      when 'structural_bibid', 'pap_structural', 'kaplan_structural', 'pqc_ark', 'pqc_combined_struct', 'pqc_combined_desc', 'pqc_structural'
        pages_with_files = []
        self.user_defined_mappings.select {|key, map| pages_with_files << map if map['file_name'].present?}
        pages_with_files.present? ? pages_with_files.sort_by.first {|p| p['serial_num']}['file_name'] : nil
    end
  end

  def filenames
    case self.source_type
    when 'custom'
      orig = ''
      self.original_mappings.each do |key, value|
        orig = value if key == self.file_field
      end
      return orig
    when 'structural_bibid', 'pap_structural', 'kaplan_structural', 'pqc_ark', 'pqc_combined_struct', 'pqc_combined_desc', 'pqc_structural'
      filenames = []
      self.user_defined_mappings.each do |key, value|
        filenames << value[self.file_field] if value[self.file_field].present?
      end
      return filenames
    when 'structural'
      self.user_defined_mappings['sequence'].map { |row| row['filename'] }
    else
      return nil
    end
  end

  def self.structural_types
    STRUCTURAL_TYPES
  end

  def validate_bib_id(bib_id)
    return bib_id.to_s.length <= 7 ? "99#{bib_id}3503681" : bib_id.to_s
  end

  private

  def csv_to_xlsx(csv)
    xlsx = csv.gsub('csv','xlsx')
    converter = CsvXlsxConverter::CsvToXlsx.new(csv)
    converter.convert(xlsx)
    return xlsx
  end

  def _catalog_xml_cleanup(mappings)
    mappings.each do |key, value|
      value = [value] unless value.respond_to?(:each)
      value.each{|v| v.strip!}
      sanitized_values = value.reject(&:empty?)
      mappings[key] = sanitized_values
    end
  end

  def reconcile_metadata_lookup_source(source_type, bib_id)
    return nil unless source_type.present?
    return "#{MetadataSchema.config[:pap][:http_lookup]}/#{bib_id}/#{MetadataSchema.config[:pap][:http_lookup_suffix]}" if %w[voyager pap pqc_desc].include?(source_type)
    return "#{MetadataSchema.config[:pap][:structural_http_lookup]}/#{bib_id}/#{MetadataSchema.config[:pap][:structural_lookup_suffix]}" if %w[structural_bibid pap_structural].include?(source_type)
  end

  def _set_marmite_data(working_path)
    _refresh_bibid(working_path) unless %w[pqc_desc pqc_ark].include?(self.source_type)
    mapped_values = {}
    catalog_source = reconcile_metadata_lookup_source(self.source_type, self.original_mappings['bibid'])
    data = Nokogiri::XML(open(catalog_source))
    data.remove_namespaces!
    nodeset = data.xpath('//records/record').children
    nodeset.each do |child|
      if child.name == 'datafield' && CustomEncodings::Marc21::Constants::TAGS[child.attributes['tag'].value].present?
        if CustomEncodings::Marc21::Constants::TAGS[child.attributes['tag'].value]['*'].present?
          if CustomEncodings::Marc21::Constants::ROLLUP_FIELDS[child.attributes['tag'].value].present?
            rollup_values = []
            header = _fetch_header_from_marc21(child)
            mapped_values["#{header}"] = [] unless mapped_values["#{header}"].present?
            child.children.each do |c|
              rollup_values << c.text unless c.text.strip.empty?
            end
            mapped_values["#{header}"] << rollup_values.join(CustomEncodings::Marc21::Constants::ROLLUP_FIELDS[child.attributes['tag'].value]['separator']) if rollup_values.present?
          else
            header = _fetch_header_from_marc21(child)
            mapped_values["#{header}"] = [] unless mapped_values["#{header}"].present?
            child.children.each do |c|
              mapped_values["#{header}"] << c.text
            end
          end
        else

          if CustomEncodings::Marc21::Constants::ROLLUP_FIELDS[child.attributes['tag'].value].present?
            rollup_values = []
            header = ''
            child.children.each do |c|
              if c.name == 'subfield'
                header = _fetch_header_from_subfield_catalog(child.attributes['tag'].value, c)
                if header.present?
                  mapped_values["#{header}"] = [] unless mapped_values["#{header}"].present?
                  c.children.each do |s|
                    rollup_values << s.text unless s.text.strip.empty?
                  end
                end
              end
            end
            mapped_values["#{header}"] << rollup_values.join(CustomEncodings::Marc21::Constants::ROLLUP_FIELDS[child.attributes['tag'].value]['separator']) if rollup_values.present?
          else
            child.children.each do |c|
              if c.name == 'subfield'
                header = _fetch_header_from_subfield_catalog(child.attributes['tag'].value, c)
                if header.present?
                  mapped_values["#{header}"] = [] unless mapped_values["#{header}"].present?
                  c.children.each do |s|
                    mapped_values["#{header}"] << s.text
                  end
                end
              end
            end
          end
        end
      end
    end
    mapped_values['identifier'] = ["#{Utils.config[:repository_prefix]}_#{self.original_mappings['bibid']}"] unless mapped_values.keys.include?('identifier')
    mapped_values['display_call_number'] = [_marmite_call_number(nodeset)]
    mapped_values.each do |entry|
      mapped_values[entry.first] = entry.last.join(' ') unless MetadataSchema.config[:voyager][:multivalue_fields].include?(entry.first)
    end
    mapped_values = _catalog_xml_cleanup(mapped_values)
    mapped_values
  end

  def _set_marmite_structural_metadata(working_path)
    mapped_values = {}
    _refresh_bibid(working_path)

    catalog_source = reconcile_metadata_lookup_source(self.source_type, self.original_mappings['bibid'])
    data = Nokogiri::XML(open(catalog_source))
    data.remove_namespaces!
    reading_direction = _get_marmite_reading_direction(catalog_source)
    data.xpath('//record/pages/page').each_with_index do |page, index|
      mapped_values[index+1] = {
          'page_number' => page['number'],
          'sequence' => page['seq'],
          'reading_direction' => reading_direction,
          'side' => page['side'],
          'tocentry' => _get_tocentry(page),
          'identifier' => page['id'],
          'file_name' => "#{page['image']}.tif",
          'description' => page['visiblepage']

      }
    end
    mapped_values
  end

  def _set_marmite_combined_metadata(working_path, source_type)
    mapped_values = {}
    marmite_source = "#{MetadataSchema.config[:combined][:http_lookup]}/#{self.metadata_builder.repo.unique_identifier.tr(":/", "+=")}/#{MetadataSchema.config[:combined][:http_lookup_suffix]}"
    data = Nokogiri::XML(open(marmite_source))
    data.remove_namespaces!
    if source_type == 'pqc_combined_desc'
      data.xpath('//record/descriptive').children.each do |child|
        (mapped_values[child.name] ||= []) << child.text unless child.name == 'text'
      end
    elsif source_type == 'pqc_combined_struct'
      reading_direction = _get_marmite_reading_direction(marmite_source)
      data.xpath('//record/pages/page').each_with_index do |page, index|
        mapped_values[index+1] = {
            'page_number' => page['number'],
            'sequence' => page['seq'],
            'reading_direction' => reading_direction,
            'side' => page['side'],
            'tocentry' => _get_tocentry(page),
            'identifier' => page['id'],
            'file_name' => "#{page['image']}.tif",
            'description' => page['visiblepage']

        }
      end
    end
    mapped_values
  end

  def _marmite_call_number(nodeset)
    call_numbers = []
    nodeset.xpath('//holdings/holding/call_number').each do |holding|
      call_numbers << holding.text if holding.text.present?
    end
    return call_numbers
  end

  def _get_tocentry(page)
    return {} unless page.children.present?
    tocentry = {}
    toc_entries = _sanitize_elements(page)
    toc_entries.each do |te|
      key = te.attributes['name'].present? ? te.attributes['name'].value : te.name
      tocentry[key] = te.children.first.text
    end
    return tocentry
  end

  def _get_marmite_reading_direction(xml_document)
    reading_direction = 'left-to-right'
    doc = Nokogiri::XML(open(xml_document))
    doc.remove_namespaces!
    doc_s = doc.xpath('//records/record/datafield[@tag="996"]')
    if doc_s.present? && doc_s.length == 1
      d = doc_s.first
      element = _sanitize_elements(d).first
      reading_direction = 'right-to-left' if element.children.first.text == 'hinge-right'
    end
    return reading_direction
  end

  def _sanitize_elements(node_set)
    return node_set.children.reject{|x| x.class == Nokogiri::XML::Text}
  end

  def _refresh_bibid(working_path)
    full_path = _reconcile_working_path_slashes(working_path, "#{self.path}")
    self.metadata_builder.repo.version_control_agent.get({:location => full_path}, working_path)
    worksheet = RubyXL::Parser.parse(full_path)
    case self.source_type
      when 'voyager', 'pap'
        page = 0
        x = 0
        y = 1
      when 'structural_bibid', 'pap_structural'
        page = 0
        x = 0
        y = 0
      else
        raise I18n.t('colenda.errors.metadata_sources.illegal_source_type')
    end
    bib_id = validate_bib_id(worksheet[page][y][x].value)
    self.original_mappings = {'bibid' => bib_id}
  end

  def _fetch_header_from_marc21(marc_field)
    CustomEncodings::Marc21::Constants::TAGS[marc_field.attributes['tag'].value]['*']
  end

  def _fetch_header_from_subfield_catalog(tag_value, marc_subfield)
    CustomEncodings::Marc21::Constants::TAGS[tag_value][marc_subfield.attributes['code'].value]
  end

  def _convert_metadata(working_path)
    begin
      pathname = Pathname.new(self.path)
      ext = pathname.extname.to_s[1..-1]
      case ext
        when 'xlsx'
          full_path = _reconcile_working_path_slashes(working_path, "#{self.path}")
          self.metadata_builder.repo.version_control_agent.get({:location => full_path}, working_path)
          @mappings = _generate_mapping_options_xlsx(full_path)
        else
          raise I18n.t('colenda.errors.metadata_sources.illegal_source_type_generic')
      end
      return @mappings
    rescue
      raise $!, I18n.t('colenda.errors.metadata_sources.conversion_error', :backtrace => $!.backtrace)
    end
  end

  def _generate_mapping_options_xlsx(full_path)
    mappings = {}
    headers = []
    iterator = 0
    x_start, y_start, x_stop, y_stop, z = _offset
    workbook = RubyXL::Parser.parse(full_path)
    case self.view_type
      when 'horizontal'
        while (x_stop >= (x_start+iterator)) && (workbook[z][y_start].present?) && (workbook[z][y_start][x_start+iterator].present?)
          header = workbook[z][y_start][x_start+iterator].value
          headers << header
          vals = []
          vals_iterator = 1
          while workbook[z][y_start+vals_iterator].present? && workbook[z][y_start+vals_iterator][x_start+iterator].present? do
            vals << workbook[z][y_start+vals_iterator][x_start+iterator].value
            vals_iterator += 1
          end
          mappings[header] = vals
          iterator += 1
        end
      when 'vertical'
        while (y_stop >= (y_start+iterator)) && (workbook[z][y_start+iterator].present?) && (workbook[z][y_start+iterator][x_start].present?)
          header = workbook[z][y_start+iterator][x_start].value
          headers << header
          vals = []
          vals_iterator = 1
          while workbook[z][y_start+iterator].present? && workbook[z][y_start+iterator][x_start+vals_iterator].present? do
            vals << workbook[z][y_start+iterator][x_start+vals_iterator].value
            vals_iterator += 1
          end
          mappings[header] = vals
          iterator += 1
        end
      else
        raise I18n.t('colenda.errors.metadata_sources.illegal_view_type', :view_type => self.view_type, :source => self.path)
    end
    mappings
  end

  def _child_values(source)
    workbook = RubyXL::Parser.parse(source)
    x_start, y_start, x_stop, y_stop, z = _offset
    content = ''
    case self.view_type
      when 'horizontal'
        self.num_objects.times do |i|
          content << "<#{self.parent_element}>"
          content << _get_row_values(workbook, i, x_start, y_start, x_stop, y_stop, z).valid_xml_text
          content << "</#{self.parent_element}>"
        end
      when 'vertical'
        self.num_objects.times do |i|
          content << "<#{self.parent_element}>"
          content << _get_column_values(workbook, i, x_start, y_start, x_stop, y_stop, z).valid_xml_text
          content << "</#{self.parent_element}>"
        end
      else
        raise I18n.t('colenda.errors.metadata_sources.illegal_source_type', :source_type => self.source_type[source], :source => source)
    end
    content
  end

  def _child_values_voyager
    content = ''
    self.user_defined_mappings.each do |entry_id, page_values|
      content << "<#{self.parent_element}>"
      page_values.each do |key, value|
        value_string = xml_value(key, value)
        content << value_string
      end
      content << "</#{self.parent_element}>"
    end
    content
  end

  def xml_value(key,value)
    value = value.nil? ? '' : value
    return '' unless [key, value].reject(&:empty?).present?
    return "<#{key.valid_xml_tag}>#{value.valid_xml_text}</#{key.valid_xml_tag}>" if value.is_a?(String)
    if value.is_a?(Hash)
      nested_values = ''
      value.each{|t,v| nested_values << "<#{t.valid_xml_tag}>#{v.valid_xml_text}</#{t.valid_xml_tag}>"}
      return "<#{key}>#{nested_values}</#{key}>"
    end
  end

  def _get_row_values(workbook, index, x_start, y_start, x_stop, y_stop, z)
    headers = workbook[z][y_start].cells.collect { |cell| cell.value }
    row_value = ''
    offset = 1
    headers.each_with_index do |header,h_index|
      field_val = workbook[z][y_start+index+offset][x_start+h_index].present? ? workbook[z][y_start+index+offset][x_start+h_index].value : ''
      row_value << "<#{self.user_defined_mappings[header]['mapped_value']}>#{field_val}</#{self.user_defined_mappings[header]['mapped_value']}>" if self.user_defined_mappings[header].present?
    end
    row_value
  end

  def _get_column_values(workbook, index, x_start, y_start, x_stop, y_stop, z)
    iterator = 0
    column_value = ''
    headers = Array.new
    while workbook[0][y_start+iterator].present? do
      headers << workbook[0][y_start+iterator][x_start].value
      iterator += 1
    end
    offset = 1
    headers.each_with_index do |header,h_index|
      field_val = workbook[z][y_start+h_index][index+offset].present? ? workbook[z][y_start+h_index][index+offset].value : ''
      column_value << "<#{self.user_defined_mappings[header]['mapped_value']}>#{field_val}</#{self.user_defined_mappings[header]['mapped_value']}>"
    end
    column_value
  end

  def _build_preservation_xml(working_path, metadata_path_and_filename, content)
    working_file = _reconcile_working_path_slashes(working_path, "#{metadata_path_and_filename}")
    preservation_file = _reconcile_working_path_slashes(working_path, "#{self.metadata_builder.repo.metadata_subdirectory}/#{self.metadata_builder.repo.preservation_filename}")
    _manage_canonical_identifier(content) if working_file == preservation_file
    tmp_filename = "#{working_file}.tmp"
    if File.basename(metadata_path_and_filename) == self.metadata_builder.repo.preservation_filename
      review_status_content = generate_review_status_xml
      content << review_status_content
    end

    File.open(tmp_filename, 'w+') do |f|
      f << $xml_header unless content.start_with?($xml_header)
      f << content
      f << $xml_footer unless content.end_with?($xml_footer)
    end
    File.rename(tmp_filename, working_file)
  end

  def _manage_canonical_identifier(xml_content)
    minted_identifier = "<#{MetadataSchema.config[:unique_identifier_field]}>#{self.metadata_builder.repo.unique_identifier}</#{MetadataSchema.config[:unique_identifier_field]}>"
    root_element = "<#{true_root_element(self)}>"

    xml_content.insert((xml_content.index(root_element)+root_element.length), minted_identifier)
  end

  def _fetch_write_save_preservation_xml(working_path, file_path = "#{self.metadata_builder.repo.metadata_subdirectory}/#{self.metadata_builder.repo.preservation_filename}", xml_content)
    file_path = _reconcile_working_path_slashes(working_path, file_path)
    self.metadata_builder.repo.version_control_agent.unlock({:content => file_path}, working_path) if File.exists?(file_path)
    _build_preservation_xml(working_path, file_path, xml_content)
    self.metadata_builder.save!
  end

  def _offset
    x_start = self.x_start - 1
    y_start = self.y_start - 1
    x_stop = self.x_stop - 1
    y_stop = self.y_stop - 1
    z = self.z - 1
    return x_start, y_start, x_stop, y_stop, z
  end

  def _strip_headers(xml)
    xml.gsub!($xml_header, '') && xml.gsub!($xml_footer, '')
  end

  def self.sheet_types
    sheet_types = [[I18n.t('colenda.metadata_sources.describe.orientation.vertical'), 'vertical'], [I18n.t('colenda.metadata_sources.describe.orientation.horizontal'), 'horizontal']]
  end

  def self.source_types
    source_types = [[I18n.t('colenda.metadata_sources.describe.source_type.list.catalog_bibid'), 'voyager'],
                    [I18n.t('colenda.metadata_sources.describe.source_type.list.structural_bibid'), 'structural_bibid'],
                    [I18n.t('colenda.metadata_sources.describe.source_type.list.pap_structural'), 'pap_structural'],
                    [I18n.t('colenda.metadata_sources.describe.source_type.list.bibliophilly'), 'bibliophilly'],
                    [I18n.t('colenda.metadata_sources.describe.source_type.list.pap'), 'pap'],
                    [I18n.t('colenda.metadata_sources.describe.source_type.list.kaplan'), 'kaplan'],
                    [I18n.t('colenda.metadata_sources.describe.source_type.list.pqc'), 'pqc'],
                    [I18n.t('colenda.metadata_sources.describe.source_type.list.pqc_structural'), 'pqc_structural'],
                    [I18n.t('colenda.metadata_sources.describe.source_type.list.custom'), 'custom']]
  end

  def self.settings_fields
    settings_fields = [:view_type, :num_objects, :x_start, :y_start, :x_stop, :y_stop]
  end

  def _reconcile_working_path_slashes(working_path, file_path)
    file_path.start_with?(working_path) ? file_path : "#{working_path}/#{file_path}".gsub("//","/")
  end
end
