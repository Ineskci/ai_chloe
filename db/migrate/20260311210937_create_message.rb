class CreateMessage < ActiveRecord::Migration[8.1]
  def change
    create_table :messages do |t|
      t.references :interview_session, null: false, foreign_key: true
      t.string :role
      t.text :content

      t.timestamps
    end
  end
end
