require 'spec_helper'

describe ReposController do

  before :each do
    @repo = FactoryGirl.create(:repo)
    @repo.create_remote
  end

  describe "GET #show" do
    it "will be refactored!"
  end

  describe "POST #checksum_log" do
    context "when files are present" do
      it "triggers checksum log creation for the repo" do
        FileUtils.touch("#{Utils.config.assets_path}/#{@repo.directory}/#{@repo.assets_subdirectory}/fake.tif")
        post :checksum_log, :id => @repo.id
        expect(flash[:success]).to be_present
      end
    end
    context "when no files are present" do
      it "returns an error that no files are present to be checksummed" do
        post :checksum_log, :id => @repo.id
        expect(flash[:error]).to be_present
      end
    end
  end


  describe "POST #prepare_for_ingest" do
    it "triggers preparation of simple XML objects for ingest to Fedora" do
      post :prepare_for_ingest, :id => @repo.id
      expect(flash[:success]).to be_present
    end

  end

  describe "POST #ingest" do
    it "triggers ingest of prepped objects into Fedora" do
      post :ingest, :id => @repo.id
      expect(flash[:success]).to be_present
    end
  end

  describe "map metadata" do
    it "should be able to detect metadata source type" do
      post :detect_metadata, :id => @repo.id
      expect(flash[:success]).to be_present
    end
    it "can convert an xlsx file to csv"
    it "can generate custom mappings for a csv to xml file"
    it "can create a flat XML file based on metadata source and user-generated mappings"
  end

end