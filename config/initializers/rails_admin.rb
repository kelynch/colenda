require Rails.root.join('lib', 'rails_admin', 'git_actions.rb')
require Rails.root.join('lib', 'rails_admin', 'create_remote.rb')
require Rails.root.join('lib', 'rails_admin', 'clone_from_production.rb')
require Rails.root.join('lib', 'rails_admin', 'sign_off_production.rb')
require Rails.root.join('lib', 'rails_admin', 'ingest.rb')
require Rails.root.join('lib', 'rails_admin', 'generate_metadata.rb')
require Rails.root.join('lib', 'rails_admin', 'file_checks.rb')
require Rails.root.join('lib', 'rails_admin', 'preview_xml.rb')
require Rails.root.join('lib', 'rails_admin', 'preserve.rb')
require Rails.root.join('lib', 'rails_admin', 'repo_new.rb')
require Rails.root.join('lib', 'rails_admin', 'batch_new.rb')
require Rails.root.join('lib', 'rails_admin', 'process_batch.rb')
require Rails.root.join('lib', 'rails_admin', 'manifest_new.rb')
require Rails.root.join('lib', 'rails_admin', 'in_queue.rb')
require Rails.root.join('lib', 'rails_admin', 'statistics.rb')
require Rails.root.join('lib', 'rails_admin', 'validate_manifest.rb')
require Rails.root.join('lib', 'rails_admin', 'create_repos.rb')
require Rails.root.join('lib', 'rails_admin', 'process_manifest.rb')

RailsAdmin::Config::Actions.register(RailsAdmin::Config::Actions::InQueue)


RailsAdmin.config do |config|
  config.main_app_name = ['Review', 'Admin Dashboard']

  config.authenticate_with do
    warden.authenticate! scope: :user
  end
  config.current_user_method(&:current_user)

  config.navigation_static_links = {
    'Front End' => '/'
  }

  config.included_models = ['Repo', 'Batch', 'Manifest']

  config.actions do
    dashboard                     # mandatory
    index
    in_queue
    statistics
    repo_new do
      only ['Repo']
    end
    batch_new do
      only ['Batch']
    end
    manifest_new do
      only ['Manifest']
    end
    git_actions do
      only ['Repo']
    end
    delete do
      only ['Batch','Manifest']
    end
    process_batch do
      only ['Batch']
    end
    preserve do
      only ['Repo']
    end
    generate_metadata do
      only ['Repo']
    end
    file_checks do
      only ['Repo']
    end
    preview_xml do
      only ['Repo']
    end
    create_remote do
      only ['Repo']
    end
    ingest do
      only ['Repo']
    end
    validate_manifest do
      only ['Manifest']
    end
    create_repos do
      only ['Manifest']
    end
    process_manifest do
      only ['Manifest']
    end
  end

  config.model Batch do
    field :queue_list, :enum do
      label 'Queue List'
      enum_method do
        :load_all_queueable
      end
      multiple do
        true
      end
      required(true)
    end
    field :directive_names do
      visible false
    end
    field :email do
      required(true)
    end
    list do
      field :queue_list do
        visible false
      end
      field :directive_names do
        visible true
        label 'Queue List'
        searchable true
        pretty_value do
          RailsAdminHelper.render_queue_names(value).html_safe
        end
      end
      field :email do
        visible true
        searchable true
      end
      field :status do
        visible true
        searchable true
      end
      field :start do
        visible true
      end
      field :end do
        visible true
      end
      field :created_at do
        visible true
        searchable true
      end
      field :updated_at do
        visible true
        searchable true
      end
    end
  end

  config.model Manifest do
    list do
      field :name
      field :owner
      field :last_action_performed do
        visible true
        searchable true
        pretty_value do
          %{#{value[:description]}}.html_safe
        end
      end
      field :created_at do
        visible true
        searchable true
      end
      field :updated_at do
        visible true
        searchable true
      end
    end

    create do
      field :uploaded_file, :file_upload do
        label I18n.t('colenda.rails_admin.manifest_new.labels.uploaded_file')
        help I18n.t('colenda.rails_admin.manifest_new.uploaded_file.help')
      end
    end
  end

  config.model Repo do
    field :human_readable_name do
      label I18n.t('colenda.rails_admin.new_repo.labels.human_readable_name')
      required(true)
    end
    field :directory_link do
      visible false
      label I18n.t('colenda.rails_admin.new_repo.labels.directory')
      pretty_value do
        %{#{value}}.html_safe
      end
    end
    field :unique_identifier do
      visible true
      label I18n.t('colenda.rails_admin.new_repo.labels.unique_identifier')
      help I18n.t('colenda.rails_admin.new_repo.unique_identifier.help')
      required(false)
    end
    field :description do
      required(false)
    end
    field :metadata_subdirectory do
      required(true)
      help I18n.t('colenda.rails_admin.new_repo.metadata_subdirectory.help')
    end
    field :assets_subdirectory do
      required(true)
      help I18n.t('colenda.rails_admin.new_repo.assets_subdirectory.help')
    end
    field :file_extensions, :enum do
      required(true)
      enum_method do
        :load_file_extensions
      end
      multiple do
        true
      end
      help I18n.t('colenda.rails_admin.new_repo.file_extensions.help')
    end
    field :metadata_source_extensions, :enum do
      required(true)
      enum_method do
        :load_metadata_source_extensions
      end
      multiple do
        true
      end
      help I18n.t('colenda.rails_admin.new_repo.metadata_source_extensions.help')
    end
    field :preservation_filename do
      required(true)
      help I18n.t('colenda.rails_admin.new_repo.preservation_filename.help')
    end
    list do
      scopes [:old_format]
      field :metadata_subdirectory do
        visible false
      end
      field :assets_subdirectory do
        visible false
      end
      field :file_extensions do
        visible false
      end
      field :metadata_source_extensions do
        visible false
      end
      field :preservation_filename do
        visible false
      end
      field :owner do
        visible true
        searchable true
      end
      field :human_readable_name do
        visible true
        searchable true
      end
      field :directory_link do
        visible true
        pretty_value do
          %{#{value}}.html_safe
        end
      end
      field :description do
        visible true
      end
      field :last_action_performed do
        visible true
        searchable true
        pretty_value do
          %{#{value[:description]}}.html_safe
        end
      end
      field :created_at do
        visible true
        searchable true
      end
      field :updated_at do
        visible true
        searchable true
      end
    end

  end

end
