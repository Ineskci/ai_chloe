class JobsController < ApplicationController
  def index
    @jobs = Job.all
  end

  def show
    redirect_to jobs_path
  end
end
