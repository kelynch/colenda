# frozen_string_literal: true

class CreateBulkImports < ActiveRecord::Migration
  def change
    create_table :bulk_imports do |t|
      t.references :created_by
      t.timestamps null: false
    end
  end
end
