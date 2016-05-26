class MetadataSourcesController < ApplicationController

  before_action :set_metadata_source, only: [:show, :edit, :update]
  before_filter :user_defined_mappings_conversion, :only => [:create, :update]

  def show
  end

  def new
    @metadata_source = MetadataSource.new
  end

  def create
    @metadata_source = MetadataSource.new(metadata_source_params)
  end

  def edit
  end

  def update
    if @metadata_source.update(metadata_source_params)
      @metadata_source.build_xml_files if @metadata_source.user_defined_mappings.present?
      redirect_to "#{root_url}admin_repo/repo/#{@metadata_source.metadata_builder.repo.id}/generate_metadata", :flash => { :success => "Metadata source successfully updated." }
    else
      redirect_to "#{root_url}admin_repo/repo/#{@metadata_source.metadata_builder.repo.id}/generate_metadata", :flash => { :error => @metadata_source.errors.messages.values.first }
    end
  end



  private

  def set_metadata_source
    @metadata_source = MetadataSource.find(params[:id])
  end

  def user_defined_mappings_conversion
    params[:metadata_source][:user_defined_mappings] = params[:metadata_source][:user_defined_mappings].to_s if params[:metadata_source][:user_defined_mappings].present?
  end

  def metadata_source_params
    params.require(:metadata_source).permit(:view_type, :num_objects, :x_start, :y_start, :x_stop, :y_stop, :original_mappings, :root_element, :parent_element, :user_defined_mappings, :children => [])
  end

end
