class CreateProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.string :name, null: false, limit: 100
      t.string :slug, null: false, limit: 100
      t.string :api_token, null: false, limit: 64
      t.timestamps
    end
    add_index :projects, :slug, unique: true
    add_index :projects, :api_token, unique: true
  end
end
