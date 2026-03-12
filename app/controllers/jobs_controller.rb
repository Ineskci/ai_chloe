class JobsController < ApplicationController
  def index
    @jobs = Job.all
  end

  def show
    @job = Job.find(params[:id])
    @chats = @job.chats.where(user: current_user)
  end
end
