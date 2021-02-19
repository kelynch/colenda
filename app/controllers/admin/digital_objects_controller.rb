module Admin
  class DigitalObjectsController < AdminController
    def index
      # Querying for repos created in the new format.
      @digital_objects = Repo.new_format.order(created_at: :desc).page(params[:page]).per(params[:per_page])
      @digital_objects = @digital_objects.id_search(params[:id_search]) if params[:id_search].present?
      @digital_objects = @digital_objects.name_search(params[:name_search]) if params[:name_search].present?
      @digital_objects = @digital_objects.where(created_by_id: params[:created_by_search]) if params[:created_by_search].present?
    end

    def show
      @digital_object = Repo.find(params[:id])
    end

    # POST publish
    # Publishes digital object to public front-end.
    def publish
      @digital_object = Repo.find(params[:id])
      success = @digital_object.publish

      if success
        public_link = catalog_url(@digital_object.names.fedora)
        flash[:success] = "Publishing was successful. View at <a class=\"alert-link\" href=\"#{public_link}\" target=\"_blank\">#{public_link}</a>"
      else
        flash[:error] = 'Error publishing digital object. Please see logs.'
      end

      redirect_to action: :show
    end
  end
end