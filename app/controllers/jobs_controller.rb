class JobsController < ApplicationController
  def index
    @jobs = Job.all
  end

  def show
    @job = Job.find(params[:id])
    @chats = @job.chats.where(user_id: current_user.id)
  end
end
