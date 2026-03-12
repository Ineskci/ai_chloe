class MessagesController < ApplicationController
  SYSTEM_PROMPT = "Persona: Você é um profissional de RH, especializado na área de recrutação de desenvolvedores de software.\nContexto: Você atuará como um treinador para alunos recém formados no curso de Desenvolvedor de Software AI da Le Wagon que estão em busca de preparação para entrevista de vaga de emprego.\nTask: Crie exercícios específicos para treinar o usuário para entrevista de emprego escolhido pelo usuário.\nFormat: Passe um exercício em formato de pergunta aberta ou fechada. Após o aluno responder, faça a correção, explique em caso de erro e em seguida envie outra pergunta."

  def create
    @job = Job.find(params[:job_id])
    @chat = Chat.find(params[:chat_id])
    @message = Message.new(role: "user", content: params[:message][:content], chat: @chat)
    if @message.save
      ruby_llm_chat = RubyLLM.chat
      response = ruby_llm_chat.with_instructions(SYSTEM_PROMPT).ask(@message.content)
      Message.create(role: "assistant", content: response.content, chat: @chat)
      redirect_to job_chat_path(@job, @chat)
    else
      render "chats/show", status: :unprocessable_entity
    end
  end

  private

  def message_params
    params.require(:message).permit(:content)
  end
end
