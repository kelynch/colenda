require 'smarter_csv'

module AutomatedWorkflows
  module Kaplan

    class Configuration
      attr_accessor :owner
      attr_accessor :description
      attr_accessor :initial_stop
      attr_accessor :metadata_fetch_method
      attr_accessor :metadata_protocol
      attr_accessor :assets_fetch_method
      attr_accessor :assets_protocol


      def initialize
        @owner = AutomatedWorkflows.config['kaplan']['csv']['owner']
        @description = AutomatedWorkflows.config['kaplan']['csv']['description']
        @initial_stop = AutomatedWorkflows.config['kaplan']['csv']['initial_stop']
        @endpoint = ''
        @metadata_suffix = AutomatedWorkflows.config['kaplan']['csv']['metadata_suffix']
        @assets_suffix = AutomatedWorkflows.config['kaplan']['csv']['assets_suffix']
        @metadata_fetch_method = AutomatedWorkflows.config['kaplan']['csv']['endpoints']['metadata_fetch_method'] || ''
        @metadata_protocol = AutomatedWorkflows.config['kaplan']['csv']['endpoints']['metadata_protocol'] || ''
        @assets_fetch_method = AutomatedWorkflows.config['kaplan']['csv']['endpoints']['assets_fetch_method'] || ''
        @assets_protocol = AutomatedWorkflows.config['kaplan']['csv']['endpoints']['assets_protocol'] || ''
      end

      def endpoint(share = 'kaplan')
        if share == 'kaplan'
          return @endpoint
        else
          return AutomatedWorkflows.config['kaplan']['csv']['nonstandard'][share]['endpoint']
        end
      end

      def metadata_suffix(share = 'kaplan')
        if share == 'kaplan'
          return @metadata_suffix
        else
          return AutomatedWorkflows.config['kaplan']['csv']['nonstandard'][share]['metadata_suffix']
        end
      end

      def assets_suffix(share = 'kaplan')
        if share == 'kaplan'
          return @assets_suffix
        else
          return AutomatedWorkflows.config['kaplan']['csv']['nonstandard'][share]['assets_suffix']
        end
      end

    end

    class Csv

      class << self
        def config
          @config ||= Configuration.new
        end

        def configure
          yield config
        end

        def convert_csv(csv_filename)
          return "#{csv_filename} not found" unless File.exist?(csv_filename)
          directories = []
          listing = SmarterCSV.process(csv_filename)
          listing.each { |row| directories << "#{row[:share]}|#{row[:path]}|#{row[:unique_identifier]}|#{row[:directive_name]}" }
          directories.uniq!
          f = File.new("#{csv_filename.gsub('.csv','.txt')}", 'w')
          directories.each { |d| f << "#{d}\n" }
          f.close
          f.path
        end

        def generate_repos(csv)
          directories_file = convert_csv(csv)
          file_lines = File.readlines(directories_file).each{|l| l.strip! }
          repos = []
          file_lines.each do |dir|
            share, directory, unique_identifier, repo_name = dir.split('|', 4)
            last_updated = DateTime.now
            repo = AutomatedWorkflows::Actions::Repos.create(repo_name,
                                                             :owner => AutomatedWorkflows::Kaplan::Csv.config.owner,
                                                             :description => AutomatedWorkflows::Kaplan::Csv.config.description,
                                                             :last_external_update => last_updated,
                                                             :initial_stop => AutomatedWorkflows::Kaplan::Csv.config.initial_stop,
                                                             :unique_identifier => unique_identifier,
                                                             :type =>'directory')

            desc = Endpoint.where(:repo => repo, :source => "#{AutomatedWorkflows::Kaplan::Csv.config.endpoint(share)}/#{directory}/#{AutomatedWorkflows::Kaplan::Csv.config.metadata_suffix(share)}", :content_type => 'metadata').first_or_create
            desc.update_attributes( :destination => repo.metadata_subdirectory,
                                    :fetch_method => AutomatedWorkflows::Kaplan::Csv.config.metadata_fetch_method,
                                    :protocol => AutomatedWorkflows::Kaplan::Csv.config.metadata_protocol,
                                    :problems => {} )
            desc.save!
            struct = Endpoint.where(:repo => repo, :source => "#{AutomatedWorkflows::Kaplan::Csv.config.endpoint(share)}/#{directory}/#{AutomatedWorkflows::Kaplan::Csv.config.assets_suffix(share)}", :content_type => 'assets').first_or_create
            struct.update_attributes( :destination => repo.assets_subdirectory,
                                      :fetch_method => AutomatedWorkflows::Kaplan::Csv.config.assets_fetch_method,
                                      :protocol => AutomatedWorkflows::Kaplan::Csv.config.assets_protocol,
                                      :problems => {} )
            struct.save!
            repo.endpoint = [desc, struct]
            AutomatedWorkflows::Agent.verify_sources(repo)
            repo.save!
            repos << repo.unique_identifier
          end
          repos
        end

      end

    end
  end
end
