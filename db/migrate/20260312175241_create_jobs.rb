class CreateJobs < ActiveRecord::Migration[8.1]
  def change
    create_table :jobs do |t|
      t.string :job_title
      t.text :job_description

      t.timestamps
    end
  end
end
