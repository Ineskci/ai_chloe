class ApplicationController < ActionController::Base
  before_action :authenticate_user!
  before_action :set_jobs
  allow_browser versions: :modern
  stale_when_importmap_changes
  before_action :configure_permitted_parameters, if: :devise_controller?

  def after_sign_in_path_for(resource)
    jobs_path
  end

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:first_name, :last_name])
    devise_parameter_sanitizer.permit(:account_update, keys: [:first_name, :last_name])
  end

  private

  def set_jobs
    @jobs = Job.all
  end
end
