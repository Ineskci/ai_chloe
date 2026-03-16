class Chat < ApplicationRecord
  belongs_to :user
  belongs_to :job
  has_many :messages, dependent: :destroy
  validates :title, length: { maximum: 50 }

  DEFAULT_TITLE = "Untitled"
  TITLE_PROMPT = <<~PROMPT
    Generate a short, descriptive, 3-to-6-word title for an interview practice session.
    You will receive the first question asked and the candidate's answer.
    The title should reflect the topic of the question (e.g. "Ruby on Rails Basics", "JavaScript Scope Question").
    Reply with only the title, no punctuation at the end.
  PROMPT

  def generate_title_from_first_message
    return unless title == DEFAULT_TITLE

    first_question = messages.where(role: "assistant").order(:created_at).offset(2).first
    first_answer   = messages.where(role: "user").order(:created_at).offset(1).first
    return if first_question.nil? || first_answer.nil?

    context = "Question: #{first_question.content}\nAnswer: #{first_answer.content}"
    response = RubyLLM.chat.with_instructions(TITLE_PROMPT).ask(context)
    update(title: response.content)
  end
end
