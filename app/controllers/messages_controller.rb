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

  TECHNICAL_TOPICS = ["Ruby on Rails", "JavaScript", "SQL", "HTML", "CSS"].freeze
  QUESTION_FORMAT = "Formato obrigatório:\n\n[enunciado da pergunta]\nA) [opção]\nB) [opção]\nC) [opção]"

  def create
    @job = Job.find(params[:job_id])
    @chat = current_user.chats.find(params[:chat_id])
    @message = Message.new(role: "user", content: params[:message][:content], chat: @chat)

    if @message.save
      @ruby_llm_chat = RubyLLM.chat(model: "gpt-4o-mini")
      @user_count = @chat.messages.where(role: "user").count
      build_conversation_history unless @user_count == 1

      process_response

      @chat.generate_title_from_first_message if @user_count >= 2

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

  def process_response
    case @user_count
    when 1 then handle_icebreaker
    when 2..5 then handle_technical_question
    when 6 then handle_last_technical_question
    when 7..8 then handle_behavioral_question
    when 9 then handle_last_behavioral_question
    end
  end

  def handle_icebreaker
    save_assistant_message ask(@message.content)
    save_assistant_message ask_fresh("Agora faça a primeira pergunta técnica sobre #{TECHNICAL_TOPICS.first}. #{QUESTION_FORMAT}")
  end

  def handle_technical_question
    save_assistant_message ask_feedback_technical
    save_assistant_message ask("Agora faça a próxima pergunta técnica. #{QUESTION_FORMAT}")
  end

  def handle_last_technical_question
    save_assistant_message ask_feedback_technical
    save_assistant_message ask("Agora faça a primeira pergunta comportamental relacionada com a vaga. #{QUESTION_FORMAT}")
  end

  def handle_behavioral_question
    save_assistant_message ask_feedback_behavioral
    save_assistant_message ask("Agora faça a próxima pergunta comportamental relacionada com a vaga. #{QUESTION_FORMAT}")
  end

  def handle_last_behavioral_question
    save_assistant_message ask_feedback_behavioral
    save_assistant_message "A entrevista terminou! 🎉"
    save_assistant_message ask("Com base em todas as respostas do candidato às 5 perguntas técnicas e 3 perguntas comportamentais, dê um feedback geral caloroso e encorajador. Destaca os pontos fortes e uma sugestão de melhoria. Máximo 4 linhas.")
    @messages_created = 4
  end

  def ask(prompt)
    @ruby_llm_chat.with_instructions(instructions).ask(prompt).content
  end

  def ask_fresh(prompt)
    RubyLLM.chat(model: "gpt-4o-mini").with_instructions(instructions).ask(prompt).content
  end

  def ask_feedback_technical
    ask("A resposta do candidato foi '#{@message.content}'. Esta resposta está correta ou incorreta? Responda apenas com 'Correto! ✅' ou 'Incorreto! ❌ A resposta correta é [X] porque [breve explicação]'")
  end

  def ask_feedback_behavioral
    ask("O candidato respondeu '#{@message.content}'. Dê um feedback curto, caloroso e encorajador. Máximo 2 linhas.")
  end

  def save_assistant_message(content)
    @chat.messages.create(role: "assistant", content: content)
  end

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
