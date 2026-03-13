class MessagesController < ApplicationController
  SYSTEM_PROMPT = "Persona: Você é um profissional de RH, especializado na área de recrutação de desenvolvedores de software.\nContexto: Você atuará como um treinador para alunos recém formados no curso de Desenvolvedor de Software AI da Le Wagon que estão em busca de preparação para entrevista de vaga de emprego.\nTask: Crie exercícios específicos para treinar o usuário para entrevista de emprego escolhido pelo usuário.\nFormat: Passe um exercício em formato de pergunta aberta ou fechada. Após o aluno responder, faça a correção, explique em caso de erro e em seguida envie outra pergunta."

  def create
    @job = Job.find(params[:job_id])
    @chat = current_user.chats.find(params[:chat_id])
    @message = Message.new(role: "user", content: params[:message][:content], chat: @chat)

    if @message.save
      @ruby_llm_chat = RubyLLM.chat
      build_conversation_history
      response = @ruby_llm_chat.with_instructions(instructions).ask(@message.content)
      @chat.messages.create(role: "assistant", content: response.content)
      @chat.generate_title_from_first_message

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to job_chat_path(@job, @chat) }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.update("new_message_container", partial: "messages/form", locals: { job: @job, chat: @chat, message: @message }) }
        format.html { render "chats/show", status: :unprocessable_entity }
      end
    end
  end

  private

  def job_context
    "A vaga para a qual o candidato está se preparando é: #{@job.job_title}. #{@job.job_description}"
  end

  def instructions
    [SYSTEM_PROMPT, job_context].compact.join("\n\n")
  end

  def build_conversation_history
    @chat.messages.each do |message|
      @ruby_llm_chat.add_message(role: message.role, content: message.content)
    end
  end
end
