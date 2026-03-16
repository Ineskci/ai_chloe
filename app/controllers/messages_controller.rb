class MessagesController < ApplicationController
  SYSTEM_PROMPT = <<~PROMPT
    ## Persona
    Você é Chloé 2.0, coach de entrevistas do Le Wagon.
    Responda SEMPRE em português do Brasil.

    ## Regras OBRIGATÓRIAS
    - SEMPRE uma mensagem por vez
    - NUNCA coloque feedback e pergunta na mesma mensagem
    - NUNCA use "Pergunta técnica:", "Pergunta comportamental:" ou "Feedback:" antes de qualquer texto
    - Escreva diretamente sem labels ou títulos

    ## Perguntas técnicas (5 no total)
    - SEMPRE 3 opções: A, B, C
    - ✅ Se acertou: apenas "Correto! ✅"
    - ❌ Se errou: "Incorreto! ❌ A resposta correta é [X] porque [breve explicação]"

    ## Perguntas comportamentais (3 no total)
    - SEMPRE 3 opções: A, B, C
    - Não há certo nem errado
    - Após a resposta: feedback curto, caloroso e encorajador (1-2 linhas)

    ## Quebra-gelo
    Responda em UMA linha — curta, calorosa e com humor. SEM label antes:
    - Se A: "Adoro a confiança! 💪 Vamos manter esse ritmo!"
    - Se B: "Normal! Nervosismo é sinal de que você se importa. 😄 Vamos lá!"
    - Se C: "Modo guerreiro ativado! 🚀 Vamos nessa!"
    Depois PARE. Não escreva mais nada.

    ## Formato
    - Sem labels, sem títulos, sem prefixos
    - Feedback: máximo 1-2 linhas
    - Pergunta técnica: enunciado + A, B, C em linhas separadas
    - Pergunta comportamental: enunciado simples e direto
  PROMPT

  def create
    @job = Job.find(params[:job_id])
    @chat = current_user.chats.find(params[:chat_id])
    @message = Message.new(role: "user", content: params[:message][:content], chat: @chat)

    if @message.save
      @ruby_llm_chat = RubyLLM.chat(model: "gpt-4o-mini")
      user_count = @chat.messages.where(role: "user").count
      build_conversation_history unless user_count == 1

      if user_count == 1
        # Quebra-gelo → resposta calorosa (sem histórico)
        response = @ruby_llm_chat.with_instructions(instructions).ask(@message.content)
        @chat.messages.create(role: "assistant", content: response.content)

        # Primeira pergunta técnica (nova instância sem histórico)
        fresh_chat = RubyLLM.chat(model: "gpt-4o-mini")
        first_question = fresh_chat.with_instructions(instructions).ask("Agora faça a primeira pergunta técnica sobre Ruby on Rails. Formato obrigatório:\n\n[enunciado da pergunta]\nA) [opção]\nB) [opção]\nC) [opção]")
        @chat.messages.create(role: "assistant", content: first_question.content)

      elsif user_count.between?(2, 5)
        # Feedback da resposta técnica
        feedback = @ruby_llm_chat.with_instructions(instructions).ask("A resposta do candidato foi '#{@message.content}'. Esta resposta está correta ou incorreta? Responda apenas com 'Correto! ✅' ou 'Incorreto! ❌ A resposta correta é [X] porque [breve explicação]'")
        @chat.messages.create(role: "assistant", content: feedback.content)

        # Próxima pergunta técnica
        next_question = @ruby_llm_chat.with_instructions(instructions).ask("Agora faça a próxima pergunta técnica. Formato obrigatório:\n\n[enunciado da pergunta]\nA) [opção]\nB) [opção]\nC) [opção]")
        @chat.messages.create(role: "assistant", content: next_question.content)

      elsif user_count == 6
        # Feedback da última resposta técnica
        feedback = @ruby_llm_chat.with_instructions(instructions).ask("A resposta do candidato foi '#{@message.content}'. Esta resposta está correta ou incorreta? Responda apenas com 'Correto! ✅' ou 'Incorreto! ❌ A resposta correta é [X] porque [breve explicação]'")
        @chat.messages.create(role: "assistant", content: feedback.content)

        # Primeira pergunta comportamental
        next_question = @ruby_llm_chat.with_instructions(instructions).ask("Agora faça a primeira pergunta comportamental relacionada com a vaga. Formato obrigatório:\n\n[enunciado da pergunta]\nA) [opção]\nB) [opção]\nC) [opção]")
        @chat.messages.create(role: "assistant", content: next_question.content)

      elsif user_count.between?(7, 8)
        # Feedback comportamental — caloroso, sem certo/errado
        feedback = @ruby_llm_chat.with_instructions(instructions).ask("O candidato respondeu '#{@message.content}'. Dê um feedback curto, caloroso e encorajador. Máximo 2 linhas.")
        @chat.messages.create(role: "assistant", content: feedback.content)

        # Próxima pergunta comportamental
        next_question = @ruby_llm_chat.with_instructions(instructions).ask("Agora faça a próxima pergunta comportamental relacionada com a vaga. Formato obrigatório:\n\n[enunciado da pergunta]\nA) [opção]\nB) [opção]\nC) [opção]")
        @chat.messages.create(role: "assistant", content: next_question.content)

      elsif user_count == 9
        # Feedback da última pergunta comportamental
        feedback = @ruby_llm_chat.with_instructions(instructions).ask("O candidato respondeu '#{@message.content}'. Dê um feedback curto, caloroso e encorajador. Máximo 2 linhas.")
        @chat.messages.create(role: "assistant", content: feedback.content)

        # Mensagem de fim de entrevista
        @chat.messages.create(role: "assistant", content: "A entrevista terminou! 🎉")

        # Feedback geral
        final_feedback = @ruby_llm_chat.with_instructions(instructions).ask("Com base em todas as respostas do candidato às 5 perguntas técnicas e 3 perguntas comportamentais, dê um feedback geral caloroso e encorajador. Destaca os pontos fortes e uma sugestão de melhoria. Máximo 4 linhas.")
        @chat.messages.create(role: "assistant", content: final_feedback.content)
      end

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
    "A vaga para a qual o candidato está se preparando é: #{@job.job_title}. #{@job.job_description}

    SEQUÊNCIA OBRIGATÓRIA — siga esta ordem exata:

    PARTE 1 — 5 perguntas técnicas (uma por mensagem):
    1. Ruby on Rails
    2. JavaScript
    3. SQL
    4. HTML
    5. CSS

    PARTE 2 — 3 perguntas comportamentais (uma por mensagem) relacionadas com #{@job.job_title}:
    - Perguntas curtas e diretas
    - Respostas curtas esperadas
    - Não há certo nem errado
    - Dê um feedback curto e caloroso após cada resposta comportamental
    - SEMPRE use opções A, B, C nas perguntas comportamentais

    TOTAL: 8 perguntas. Não repita perguntas. Não salte nenhuma."
  end

  def instructions
    [SYSTEM_PROMPT, job_context].compact.join("\n\n")
  end

  def build_conversation_history
    @chat.messages.last(10).each do |message|
      @ruby_llm_chat.add_message(role: message.role, content: message.content)
    end
  end
end
