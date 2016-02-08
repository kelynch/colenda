require Rails.root.join('lib', 'rails_admin', 'git_review.rb')
require Rails.root.join('lib', 'rails_admin', 'create_remote.rb')
require Rails.root.join('lib', 'rails_admin', 'clone_from_production.rb')
require Rails.root.join('lib', 'rails_admin', 'sign_off_production.rb')
require Rails.root.join('lib', 'rails_admin', 'report_flagged.rb')
require Rails.root.join('lib', 'rails_admin', 'preprocess_review.rb')
require Rails.root.join('lib', 'rails_admin', 'map_metadata.rb')

RailsAdmin.config do |config|
  config.main_app_name = ["Intermediary", "Admin Interface"]

  config.included_models = ["Repo"]

  config.actions do
    dashboard                     # mandatory
    index                         # mandatory
    new
    export
    bulk_delete
    show
    edit
    delete
    map_metadata
    git_review do
      only ["Repo"]
    end
    create_remote do
      only ["Repo"]
    end
    preprocess_review do
      only ["Repo"]
    end
  end

  config.model Repo do
    field :title do
      required(true)
    end
    field :directory do
      required(true)
      help "Required - directory on the remote filesystem that will serve as the location for the git repository"
    end
    field :identifier do
      required(false)
    end
    field :description do
      required(false)
    end
    field :metadata_subdirectory do
      required(true)
      help "Required - subdirectory within the directory specified above that will serve as the location for the metadata to be processed by the application"
    end
    field :assets_subdirectory do
      required(true)
      help "Required - subdirectory within the directory specified above that will serve as the location for the assets to be processed by the application"
    end
    field :metadata_filename do
      required(true)
      help "Required - name of the metadata file in the metadata subdirectory to be processed by the application"
    end
    field :file_extensions do
      required(true)
      help "Required - comma-separated list of accepted file extensions for assets to be served to production from the assets subdirectory.  Example: jpeg,tif"
    end
    field :metadata_sources do
      required(false)
    end

  end

end
