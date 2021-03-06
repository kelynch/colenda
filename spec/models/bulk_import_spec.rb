# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BulkImport, type: :model do
  let(:bulk_import) do
    FactoryBot.build :bulk_import,
                     digital_object_imports: FactoryBot.build_list(:digital_object_import, 1)
  end

  it 'has many DigitalObjectImports' do
    expect(bulk_import.digital_object_imports).to be_a ActiveRecord::Associations::CollectionProxy
    expect(bulk_import.digital_object_imports.first).to be_a DigitalObjectImport
  end

  it 'returns a User using created_by' do
    expect(bulk_import.created_by).to be_a User
  end

  it 'has timestamps' do
    expect(bulk_import).to respond_to :created_at, :updated_at
  end

  describe '.aggregate_processing_time' do
    let(:import_1) { FactoryBot.build(:digital_object_import, :successful, duration: 60) }
    let(:import_2) { FactoryBot.build(:digital_object_import, :successful, duration: 120) }
    let(:bulk_import) { FactoryBot.create(:bulk_import, digital_object_imports: [import_1, import_2]) }

    it 'sums the processing time of child DigitalObjectImports' do
      expect(bulk_import.aggregate_processing_time).to eq 180
    end
  end

  describe '.valid?' do
    context 'when created_by not present' do
      let(:bulk_import) { FactoryBot.build(:bulk_import, created_by: nil) }

      it 'returns error' do
        expect(bulk_import.valid?).to be false
        expect(bulk_import.errors.messages[:created_by]).to include "can't be blank"
      end
    end
  end

  describe '.status' do
    context 'when all imports are queued' do
      let(:import_1) { FactoryBot.build(:digital_object_import, :queued) }
      let(:import_2) { FactoryBot.build(:digital_object_import, :queued) }
      let(:bulk_import) { FactoryBot.create(:bulk_import, digital_object_imports: [import_1, import_2]) }

      it 'returns queued' do
        expect(bulk_import.status).to eql BulkImport::QUEUED
      end
    end

    context 'when no imports are present' do
      let(:bulk_import) { FactoryBot.create(:bulk_import) }

      it 'returns nil' do
        expect(bulk_import.status).to be_nil
      end
    end

    context 'when any imports are in progress' do
      let(:import_1) { FactoryBot.build(:digital_object_import, :in_progress) }
      let(:import_2) { FactoryBot.build(:digital_object_import, :queued) }
      let(:bulk_import) { FactoryBot.create(:bulk_import, digital_object_imports: [import_1, import_2]) }

      it 'returns in progress' do
        expect(bulk_import.status).to eql BulkImport::IN_PROGRESS
      end
    end

    context 'when all imports are successful' do
      let(:import_1) { FactoryBot.build(:digital_object_import, :successful) }
      let(:import_2) { FactoryBot.build(:digital_object_import, :successful) }
      let(:bulk_import) { FactoryBot.create(:bulk_import, digital_object_imports: [import_1, import_2]) }

      it 'returns completed' do
        expect(bulk_import.status).to eql BulkImport::COMPLETED
      end
    end

    context 'when all imports failed' do
      let(:import_1) { FactoryBot.build(:digital_object_import, :failed) }
      let(:import_2) { FactoryBot.build(:digital_object_import, :failed) }
      let(:bulk_import) { FactoryBot.create(:bulk_import, digital_object_imports: [import_1, import_2]) }

      it 'returns completed' do
        expect(bulk_import.status).to eql BulkImport::COMPLETED_WITH_ERRORS
      end
    end

    context 'when all imports are successful or failures' do
      let(:import_1) { FactoryBot.build(:digital_object_import, :failed) }
      let(:import_2) { FactoryBot.build(:digital_object_import, :successful) }
      let(:bulk_import) { FactoryBot.create(:bulk_import, digital_object_imports: [import_1, import_2]) }

      it 'returns completed' do
        expect(bulk_import.status).to eql BulkImport::COMPLETED_WITH_ERRORS
      end
    end

    context 'when imports are successful or queued' do
      let(:import_1) { FactoryBot.build(:digital_object_import, :queued) }
      let(:import_2) { FactoryBot.build(:digital_object_import, :successful) }
      let(:bulk_import) { FactoryBot.create(:bulk_import, digital_object_imports: [import_1, import_2]) }

      it 'returns in progress' do
        expect(bulk_import.status).to eql BulkImport::IN_PROGRESS
      end
    end

    context 'when all completed imports have failed but some are still running' do
      let(:import_1) { FactoryBot.build(:digital_object_import, :failed) }
      let(:import_2) { FactoryBot.build(:digital_object_import, :in_progress) }
      let(:import_3) { FactoryBot.build(:digital_object_import, :queued) }

      let(:bulk_import) { FactoryBot.create(:bulk_import, digital_object_imports: [import_1, import_2, import_3]) }

      it 'returns in progress' do
        expect(bulk_import.status).to eql BulkImport::IN_PROGRESS
      end
    end

    context 'when all completed imports have succeeded but some are still running' do
      let(:import_1) { FactoryBot.build(:digital_object_import, :successful) }
      let(:import_2) { FactoryBot.build(:digital_object_import, :in_progress) }
      let(:import_3) { FactoryBot.build(:digital_object_import, :queued) }

      let(:bulk_import) { FactoryBot.create(:bulk_import, digital_object_imports: [import_1, import_2, import_3]) }

      it 'returns in progress' do
        expect(bulk_import.status).to eql BulkImport::IN_PROGRESS
      end
    end
  end
end
