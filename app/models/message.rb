class Message < ApplicationRecord
  belongs_to :chat

  MAX_USER_MESSAGES = 10

  validate :user_message_limit, if: -> { role == "user" }

  # After a message is created, broadcast it to the chat channel
  # This appends the new message HTML to the #messages div in real time
  after_create_commit :broadcast_append_to_chat

  private

  def broadcast_append_to_chat
    broadcast_append_to chat,
      target: "messages",
      partial: "messages/message",
      locals: { message: self }
  end

  def user_message_limit
    if chat.messages.where(role: "user").count >= MAX_USER_MESSAGES
      errors.add(:content, "You can only send #{MAX_USER_MESSAGES} messages per chat.")
    end
  end
end
