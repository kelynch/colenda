require 'open-uri'

class MetadataSource < ActiveRecord::Base

  include Utils::Artifacts::InputFormats

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
    self.metadata_builder.repo.update_steps(:metadata_source_type_specified)
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

  def input_source_path(source_type)
    case source_type
      when 'custom', 'bibliophilly'
        self.path
      when 'voyager'
        "#{MetadataSchema.config[:voyager][:http_lookup]}/#{self.original_mappings['bibid']}.xml"
      when 'structural_bibid'
        "#{MetadataSchema.config[:voyager][:structural_http_lookup]}#{MetadataSchema.config[:voyager][:structural_identifier_prefix]}#{self.original_mappings['bibid']}"
      else
        nil
    end
  end

  def set_metadata_mappings(working_path)
    binding.pry
    if self.source_type.present?
      case self.source_type
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
          self.user_defined_mappings = _set_voyager_structural_metadata(working_path)
          self.identifier = self.original_mappings['bibid']
        when 'voyager'
          self.root_element = MetadataSchema.config[:voyager][:root_element] || 'record'
          self.user_defined_mappings = _set_voyager_data(working_path)
          self.identifier = self.original_mappings['bibid']
        when 'bibliophilly'
          self.set_bibliophilly_data(working_path)
          self.identifier = self.original_mappings['Call Number/ID'].first
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

  def generate_all_xml(working_path)
    self.generate_and_build_individual_xml(working_path)
    self.children.each do |child|
      source = MetadataSource.find(child)
      source.generate_and_build_individual_xml(working_path, source.path) unless %w[bibliophilly_structural].include?(source.source_type)
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
    Dir.chdir(working_path)
    `xsltproc #{Rails.root}/lib/tasks/pqc_mets.xslt #{file_name}`
    pqc_path = "#{working_path}/#{self.metadata_builder.repo.metadata_subdirectory}/#{Utils.config['mets_xml_derivative']}"
    FileUtils.mv(Utils.config["mets_xml_derivative"], pqc_path) if Utils.config["mets_xml_derivative"].present?
  end

  def jettison_metadata(working_path, files_to_jettison)
    files_to_jettison.each do |f|
      f = _reconcile_working_path_slashes(working_path, f)
      self.metadata_builder.repo.version_control_agent.unlock({:content => f}, working_path)
      self.metadata_builder.repo.version_control_agent.drop({:drop_location => f}, working_path) && `rm -rf #{Shellwords.escape(f)}`
    end
    $jettison_files = Set.new
  end

  def generate_and_build_individual_xml(working_path, fname = self.path)
    xml_fname = "#{fname}.xml"
    if self.user_defined_mappings.present? && self.root_element.present?
      case self.source_type
        when 'custom'
          @xml_content_final_copy = xml_from_custom(working_path, fname)
        when 'voyager', 'pap'
          @xml_content_final_copy = xml_from_voyager
        when 'structural_bibid', 'pap_structural'
          @xml_content_final_copy = xml_from_structural_bibid
        when 'bibliophilly'
          @xml_content_final_copy = xml_from_flat_mappings
      end
      $jettison_files.add(xml_fname)
      _fetch_write_save_preservation_xml(working_path, xml_fname, @xml_content_final_copy)
    end
  end

  def generate_preservation_xml(working_path)
    if (self.children.present? || (parent_id = check_parentage).present?) && self.source_type != 'bibliophilly' && self.source_type != 'kaplan'
      @xml_content_final = parent_id.present? ? MetadataSource.find(parent_id).generate_parent_child_xml(working_path) : self.generate_parent_child_xml(working_path)
    else
      file = File.new(_reconcile_working_path_slashes(working_path, "#{self.path}.xml"))
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
    self.user_defined_mappings.each do |mapping|
      tag = mapping.first.valid_xml_tag
      mapping.last.each do |value|
        parent_content << "<#{tag}>#{value.to_s.valid_xml_text}</#{tag}>"
      end
    end
    structural = MetadataSource.find(self.children.first)
    structural.user_defined_mappings.each do |mapping|
      child_content << "<#{structural.parent_element}>"
      mapping.last.each do |key, value|
        child_content << "<#{key.valid_xml_tag}>#{value.to_s.valid_xml_text}</#{key.valid_xml_tag}>"
      end
      child_content << "</#{structural.parent_element}>"
    end
    "<#{self.root_element}>#{parent_content}<#{structural.root_element}>#{child_content}</#{structural.root_element}></#{self.root_element}>"
  end

  def generate_parent_child_xml(working_path)
    content = ''
    key_path = _reconcile_working_path_slashes(working_path, "#{self.path}.xml")
    self.generate_and_build_individual_xml(working_path)
    self.children.each do |child|
      child_path = MetadataSource.where(:id => child).pluck(:path).first
      child_content_path = _reconcile_working_path_slashes(working_path, "#{child_path}.xml")
      self.metadata_builder.repo.version_control_agent.get({:location => key_path}, working_path)
      self.metadata_builder.repo.version_control_agent.get({:location => child_content_path}, working_path)
      content = File.open(key_path, 'r'){|io| io.read}
      child_inner_content = File.open(child_content_path, 'r'){|io| io.read}
      _strip_headers(content) && _strip_headers(child_inner_content)
      end_tag = "</#{self.root_element}>"
      insert_index = content.index(end_tag)
      content.insert(insert_index, child_inner_content)
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

  def set_bibliophilly_data(working_path)
    self.root_element = 'record'
    self.view_type = 'vertical'
    self.y_start = 6
    self.y_stop = 72
    self.x_start = 2
    structural = self.metadata_builder.metadata_source.any? {|a| a.source_type == 'bibliophilly_structural'} ? MetadataSource.find(self.children.first) : initialize_bibliophilly_structural(self)
    full_path = "#{working_path}#{self.path}"
    self.metadata_builder.repo.version_control_agent.get({:location => full_path}, working_path)
    self.generate_bibliophilly_descrip_md(full_path)
    structural.generate_bibliophilly_struct_md(full_path)
  end

  def generate_bibliophilly_descrip_md(full_path)
    mappings = {}
    iterator = 0
    x_start, y_start, x_stop, y_stop, z = _offset
    workbook = RubyXL::Parser.parse(full_path)
    (y_start..y_stop).each do |i|
      if workbook[z][y_start+iterator].present? && workbook[z][y_start+iterator][x_start].present?
        header = workbook[z][y_start+iterator][x_start].value
        vals = []
        vals_iterator = 2
        while workbook[z][y_start+iterator].present? && workbook[z][y_start+iterator][x_start+vals_iterator].present? do
          vals << workbook[z][y_start+iterator][x_start+vals_iterator].value.to_s.encode(:xml => :text) if workbook[z][y_start+iterator][x_start+vals_iterator].value.present?
          vals_iterator += 1
        end
        mappings[header] = vals if header.present? && vals.present?
      end
      iterator += 1
    end
    self.original_mappings = mappings
    self.user_defined_mappings = mappings
    self.save!
  end

  def generate_bibliophilly_struct_md(full_path)
    mappings = {}
    headers = []
    x_start, y_start, x_stop, y_stop, z = _offset
    workbook = RubyXL::Parser.parse(full_path)
    iterator = 1
    workbook[z][y_start].cells.each do |c|
      headers << c.value
    end
    while workbook[z][y_start+iterator].present? && workbook[z][y_start+iterator][x_start+1].present? && workbook[z][y_start+iterator][x_start+1].value.present? do
      iterator += 1
    end
    num_pages = iterator - 1
    (1..(num_pages)).each do |i|
      mapped_values = {}
      workbook[z][y_start+i].cells.each do |c|
        xml_value = c.present? ? (c.value.is_a?(Float) && headers[c.column].downcase == 'serial_num') ? c.value.to_i : c.value.to_s : ''
        mapped_values[headers[c.column].downcase] = xml_value.to_s.valid_xml_text if xml_value.present?
      end
      mappings[i] = mapped_values
    end
    self.original_mappings = mappings
    self.user_defined_mappings = mappings
    self.save!
  end


  def initialize_bibliophilly_structural(parent)
    struct = MetadataSource.create({
                                       :metadata_builder => self.metadata_builder,
                                       :source_type => 'bibliophilly_structural',
                                       :root_element => 'pages',
                                       :parent_element => 'page',
                                       :view_type => 'horizontal',
                                       :path => "#{parent.path} Page 2 (Structural)",
                                       :file_field => 'file_name',
                                       :z => 2,
                                       :y_start => 3,
                                       :y_stop => 3,
                                       :x_start => 1,
                                       :x_stop => 3 })
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
      when 'structural_bibid', 'bibliophilly_structural'
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
      when 'structural_bibid', 'bibliophilly_structural', 'pap_structural'
        filenames = []
        self.user_defined_mappings.each do |key, value|
          filenames << value[self.file_field] if value[self.file_field].present?
        end
        return filenames
      else
        return nil
    end
  end

  def self.structural_types
    %w[custom structural_bibid bibliophilly_structural pap_structural]
  end

  private

  def _set_voyager_data(working_path)
    _refresh_bibid(working_path)
    mapped_values = {}
    voyager_source = reconcile_metadata_lookup_source(self.source_type, self.original_mappings['bibid'])
    data = Nokogiri::XML(open(voyager_source))
    nodeset = data.xpath('//page/response/result/doc/xml[@name="marcrecord"]').children.first
    nodeset.children.each do |child|
      if child.name == 'datafield' && CustomEncodings::Marc21::Constants::TAGS[child.attributes['tag'].value].present?
        if CustomEncodings::Marc21::Constants::TAGS[child.attributes['tag'].value]['*'].present?
          header = _fetch_header_from_marc21(child)
          mapped_values["#{header}"] = [] unless mapped_values["#{header}"].present?
          child.children.each do |c|
            mapped_values["#{header}"] << c.text
          end
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
    mapped_values['identifier'] = ["#{Utils.config[:repository_prefix]}_#{self.original_mappings['bibid']}"] unless mapped_values.keys.include?('identifier')
    mapped_values['collection'] = [_get_catalog_collection(self.source_type, self.original_mappings['bibid'])]
    mapped_values.each do |entry|
      mapped_values[entry.first] = entry.last.join(' ') unless MetadataSchema.config[:voyager][:multivalue_fields].include?(entry.first)
    end
    mapped_values = _catalog_xml_cleanup(mapped_values)
    mapped_values
  end

  def _catalog_xml_cleanup(mappings)
    mappings.each do |key, value|
      value = [value] unless value.respond_to?(:each)
      value.each{|v| v.strip!}
      sanitized_values = value.reject(&:empty?)
      mappings[key] = sanitized_values
    end
  end

  def _get_catalog_collection(source_type, bib_id)
    voyager_source = reconcile_metadata_lookup_source(source_type, bib_id)
    data = Nokogiri::XML(open(voyager_source))
    data.remove_namespaces!
    collection_name = data.xpath('//page/collection/name').children.first.text
    return collection_name
  end

  def reconcile_metadata_lookup_source(source_type, bib_id)
    return nil unless source_type.present?
    return "#{MetadataSchema.config[:voyager][:http_lookup]}#{MetadataSchema.config[:voyager][:structural_identifier_prefix]}#{bib_id}" if %w[voyager structural_bibid].include?(source_type)
    return "#{MetadataSchema.config[:pap][:http_lookup]}/#{bib_id}/#{MetadataSchema.config[:pap][:http_lookup_suffix]}" if source_type == 'pap'
    return "#{MetadataSchema.config[:pap][:structural_http_lookup]}/#{bib_id}/#{MetadataSchema.config[:pap][:structural_lookup_suffix]}" if source_type == 'pap_structural'

  end

  #TODO: Refactor to use config variables
  def _set_voyager_structural_metadata(working_path)
    mapped_values = {}
    _refresh_bibid(working_path)
    voyager_source = reconcile_metadata_lookup_source(self.source_type, self.original_mappings['bibid'])
    data = Nokogiri::XML(open(voyager_source))
    reading_direction = _get_catalog_reading_direction(voyager_source)
    data.xpath('//xml/page').each_with_index do |page, index|
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

  def _set_marmite_data(working_path)
    _refresh_bibid(working_path)
    mapped_values = {}
    catalog_source = reconcile_metadata_lookup_source(self.source_type, self.original_mappings['bibid'])
    data = Nokogiri::XML(open(catalog_source))
    data.remove_namespaces!
    nodeset = data.xpath('//records/record').children
    nodeset.each do |child|
      if child.name == 'datafield' && CustomEncodings::Marc21::Constants::TAGS[child.attributes['tag'].value].present?
        if CustomEncodings::Marc21::Constants::TAGS[child.attributes['tag'].value]['*'].present?
          header = _fetch_header_from_marc21(child)
          mapped_values["#{header}"] = [] unless mapped_values["#{header}"].present?
          child.children.each do |c|
            mapped_values["#{header}"] << c.text
          end
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
    mapped_values['identifier'] = ["#{Utils.config[:repository_prefix]}_#{self.original_mappings['bibid']}"] unless mapped_values.keys.include?('identifier')
    mapped_values['collection'] = [_collection_name(self.source_type)]
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

  def _collection_name(source_type)
    return 'Print at Penn: Selected Printed Works' if source_type == 'pap'
    return ''
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
      tocentry[te.attributes['name'].value] = te.children.first.text
    end
    return tocentry
  end

  def _get_catalog_reading_direction(xml_document)
    reading_direction = 'left-to-right'
    doc = Nokogiri::XML(open(xml_document))
    doc.remove_namespaces!
    doc_s = doc.xpath('//xml/record/datafield[@tag="996"]')
    if doc_s.present? && doc_s.length == 1
      d = doc_s.first
      element = _sanitize_elements(d).first
      reading_direction = 'right-to-left' if element.children.first.text == 'hinge-right'
    end
    return reading_direction
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
    self.original_mappings = {'bibid' => worksheet[page][y][x].value}
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

  def     _manage_canonical_identifier(xml_content)
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
    source_types = [[I18n.t('colenda.metadata_sources.describe.source_type.list.catalog_bibid'), 'voyager'], [I18n.t('colenda.metadata_sources.describe.source_type.list.structural_bibid'), 'structural_bibid'], [I18n.t('colenda.metadata_sources.describe.source_type.list.pap_structural'), 'pap_structural'], [I18n.t('colenda.metadata_sources.describe.source_type.list.bibliophilly'), 'bibliophilly'], [I18n.t('colenda.metadata_sources.describe.source_type.list.pap'), 'pap'], [I18n.t('colenda.metadata_sources.describe.source_type.list.custom'), 'custom']]
  end

  def self.settings_fields
    settings_fields = [:view_type, :num_objects, :x_start, :y_start, :x_stop, :y_stop]
  end

  def _reconcile_working_path_slashes(working_path, file_path)
    file_path.start_with?(working_path) ? file_path : "#{working_path}/#{file_path}".gsub("//","/")
  end


  # def _build_spreadsheet_derivative(spreadsheet_values, options = {})
  #   spreadsheet_derivative_path = "#{@working_path}/#{Utils.config[:object_derivatives_path]}/#{self.original_mappings["bibid"]}.xlsx"
  #   self.metadata_builder.metadata_source << MetadataSource.create(path: spreadsheet_derivative_path, source_type: "voyager_derivative", view_type: options[:view_type], x_start: options[:x_start], y_start: options[:y_start], x_stop: options[:x_stop], y_stop: options[:y_stop]) unless self.metadata_builder.metadata_source.where(metadata_builder_id: self.metadata_builder.id).pluck(:path) == spreadsheet_derivative_path
  #   self.metadata_builder.save!
  #   workbook = RubyXL::Workbook.new
  #   worksheet = workbook[0]
  #   spreadsheet_values.keys.each_with_index do |key, k_index|
  #     worksheet.add_cell(0, k_index, key)
  #     spreadsheet_values[key].each_with_index do |val, v_index|
  #       worksheet.add_cell(v_index+1,k_index,val)
  #     end
  #   end
  #   workbook.write(spreadsheet_derivative_path)
  #   self.metadata_builder.repo.version_control_agent.commit(I18n.t('colenda.version_control_agents.commit_messages.catalog_derivative_spreadsheet'))
  #   self.metadata_builder.repo.version_control_agent.push
  #   generate_and_build_individual_xml("#{@working_path}/#{Utils.config[:object_derivatives_path]}/#{self.original_mappings["bibid"]}.xlsx")
  # end

end