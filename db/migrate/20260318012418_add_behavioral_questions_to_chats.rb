class AddBehavioralQuestionsToChats < ActiveRecord::Migration[8.1]
  def change
    add_column :chats, :behavioral_questions, :text
  end
end
