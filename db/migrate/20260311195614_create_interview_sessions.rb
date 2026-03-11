class CreateInterviewSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :interview_sessions do |t|
      t.string :job_url
      t.text :description
      t.text :job_context
      t.text :cv_context
      t.string :interview_type
      t.text :feedback

      t.timestamps
    end
  end
end
