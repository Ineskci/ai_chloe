class ChatsController < ApplicationController
  def new
    @job = Job.find(params[:job_id])
    @chat = Chat.new
  end

  def create
    @job = Job.find(params[:job_id])

    @chat = Chat.new(title: Chat::DEFAULT_TITLE)
    @chat.job = @job
    @chat.user = current_user

    if @chat.save
      first_name = current_user.first_name.presence || current_user.email

      # Primeira caixa — saudação (texto fixo)
      @chat.messages.create(role: "assistant", content: "Olá, #{first_name}! 👋 Eu sou a Chloé 2.0, sua coach de entrevistas! Pronto para treinar sua entrevista de #{@job.job_title}?")

      # Segunda caixa — quebra-gelo (resposta livre)
      @chat.messages.create(role: "assistant", content: "Antes de começarmos, conta-me: como você está se sentindo hoje para essa entrevista?")

      redirect_to job_chat_path(@job, @chat)
    else
      @chats = @job.chats.where(user_id: current_user.id)
      render "jobs/show"
    end
  end

  def show
    @job = Job.find(params[:job_id])
    @chat = current_user.chats.find(params[:id])
    @message = Message.new
    @messages = @chat.messages
  end

  private

  def destroy
    @job = Job.find(params[:job_id])
    @chat = current_user.chats.find(params[:id])
    @chat.destroy
    redirect_to job_path(@job), notice: "Sessão apagada."
  end

  def job_context
    "O candidato está se preparando para a vaga de: #{@job.job_title}. #{@job.job_description}"
  end
end
