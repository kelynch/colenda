require "rexml/document"

module RailsAdminHelper

  include CatalogHelper
  include MetadataBuilderHelper
  include MetadataSourceHelper
  include RepoHelper

  def render_git_remote_options
    render_git_directions_or_actions
  end

  def render_ingest_select_form
    render_ingest_or_message
  end

  def render_ingest_links
    render_ingested_list
  end

  def render_review_box
    repo = Repo.where("ingested = ?", [@document.id].to_yaml).first!
    render_review_status(repo)
  end

  def get_job_status(job_id)
    ActiveJobStatus::JobStatus.get_status(job_id: job_id)
  end

  def render_template_based_on_status(process,job_id)
    render :partial => job_based_partial(process, job_id)
  end

  def root_element_options
    return MetadataSchema.config[:root_element_options]
  end

  def parent_element_options
    return MetadataSchema.config[:parent_element_options]
  end

  def schema_terms
    return MetadataSchema.config[:schema_terms]
  end

  def schema_term_default(source_value)
    schema_terms = MetadataSchema.config[:schema_terms].map(&:downcase)
    if schema_terms.index(source_value).present?
      best_guess = schema_terms[schema_terms.index(source_value)]
    elsif schema_terms.index { |s| s.starts_with?(source_value.first.downcase) }.present?
      best_guess = schema_terms[schema_terms.index { |s| s.starts_with?(source_value.first.downcase) }]
    else
      best_guess = schema_terms.first
    end
    return best_guess
  end

  def attributes_display(object)
    atrributes_for_display = {}
    object.attribute_names.sort.each do |a_name|
      if object.try(a_name).present?
        items_for_display = []
        Array[object.try(a_name)].flatten(1).each do |value|
          items_for_display << value
        end
        atrributes_for_display[a_name.capitalize.to_sym] = items_for_display
      end
    end
    attributes_display = ""
    atrributes_for_display.each do |key, values|
      items = wrap_values(values)
      attributes_display << content_tag(:strong, key)
      attributes_display << content_tag(:ul, items)
    end
    return attributes_display
  end

  def wrap_values(values)
    formatted = ""
    values.each do |value|
      formatted << content_tag(:li, value.blank? ? "N/A" : value)
    end
    return formatted.html_safe
  end

  def form_label(form_type, repo_steps)
    case form_type
    when "generate_xml"
      repo_steps[:preservation_xml_generated] ? t('colenda.rails_admin.labels.generate_xml.additional_times') : t('colenda.rails_admin.labels.generate_xml.first_time')
    when "source_select"
      repo_steps[:metadata_sources_selected] ? t('colenda.rails_admin.labels.source_select.additional_times') : t('colenda.rails_admin.labels.source_select.first_time')
    when "metadata_mappings"
      repo_steps[:metadata_mappings_generated] ? t('colenda.rails_admin.labels.metadata_mappings.additional_times') : t('colenda.rails_admin.labels.metadata_mappings.first_time')
    when "extract_metadata"
      repo_steps[:metadata_extracted] ? t('colenda.rails_admin.labels.extract_metadata.additional_times') : t('colenda.rails_admin.labels.extract_metadata.first_time')
    when "metadata_source_additional_info"
      repo_steps[:metadata_source_additional_info_set] ? t('colenda.rails_admin.labels.metadata_source_additional_info.additional_times'): t('colenda.rails_admin.labels.metadata_source_additional_info.first_time')
    when "set_source_types"
      repo_steps[:metadata_source_type_specified] ? t('colenda.rails_admin.labels.set_source_types.additional_times') : t('colenda.rails_admin.labels.set_source_types.first_time')
    when "publish_preview"
      repo_steps[:published_preview] ? t('colenda.rails_admin.labels.publish_preview.additional_times') : t('colenda.rails_admin.labels.publish_preview.first_time')
    else
      "Submit"
    end
  end

  def job_based_partial(process, job_id)
    case process
    when "ingest"
      ready_partial = "rails_admin/main/ingest_dashboard"
    when "metadata_extraction"
      ready_partial = "rails_admin/main/extract_and_map_metadata"
    when "generate_xml"
      ready_partial = "rails_admin/main/preview_xml"
    else
      ready_partial = "shared/generic_error"
    end
    (get_job_status(job_id) == :queued) || (get_job_status(job_id) == :working) ? "shared/waiting" : ready_partial
  end

end
