require 'rails_helper'

RSpec.describe Page, type: :model do
  it "has a valid factory" do
    expect(FactoryGirl.create(:page)).to be_valid
  end
  it "is invalid without a page ID" do
    expect(FactoryGirl.build(:page, :page_id => nil)).not_to be_valid
  end
  it "is invalid without a parent manuscript" do
    expect(FactoryGirl.build(:page, :parent_manuscript => nil)).not_to be_valid
  end
  it "is the child of an existing manuscript"
end
