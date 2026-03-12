class ChatsController < ApplicationController
  def new
    @job = Job.find(params[:job_id])
    @chat = Chat.new
  end

  def create
    @job = Job.find(params[:job_id])

    @chat = Chat.new(title: "Untitled")
    @chat.job = @job
    @chat.user = current_user

    if @chat.save
      redirect_to job_chat_path(@job, @chat)
    else
      @chats = @job.chats.where(user_id: current_user.id)
      render "jobs/show"
    end
  end

  def show
    @chat    = current_user.chats.find(params[:id])
    @message = Message.new
  end
end
