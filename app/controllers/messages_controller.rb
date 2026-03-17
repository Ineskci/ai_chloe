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

    ## Quebra-gelo
    Responda de forma calorosa, simpática e com humor à resposta do candidato.
    Depois PARE. Não escreva mais nada.

    ## Perguntas técnicas (5 no total)
    - Perguntas abertas — o candidato responde livremente
    - Se acertou: parabenize de forma calorosa e breve (1 linha)
    - Se errou: corrija de forma calorosa e encorajadora. Explique a resposta correta em máximo 1 linha

    ## Perguntas comportamentais (3 no total)
    - Perguntas abertas — o candidato responde livremente
    - Não há certo nem errado
    - Após a resposta: feedback curto, caloroso e encorajador (1 linha)

    ## Formato
    - Sem labels, sem títulos, sem prefixos
    - Feedback: máximo 1-2 linhas
    - Perguntas: diretas e concisas
  PROMPT

  TECHNICAL_TOPICS = ["Ruby on Rails", "JavaScript", "SQL", "HTML", "CSS"].freeze
  QUESTION_FORMAT = "Faça uma pergunta direta e concisa. Não uses opções A, B, C — o candidato responde livremente."

  def create
    @job = Job.find(params[:job_id])
    @chat = current_user.chats.find(params[:chat_id])
    @message = Message.new(role: "user", content: params[:message][:content], chat: @chat)

    if @message.save
      @ruby_llm_chat = RubyLLM.chat(model: "gpt-4o-mini")
      @user_count = @chat.messages.where(role: "user").count
      # Don't load history for the first message — fresh start
      build_conversation_history unless @user_count == 1

      # Route to the correct handler based on where we are in the interview
      process_response

      # Generate a title from the first user message (from message 2 onwards)
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

  # Routes to the correct handler based on how many user messages have been sent
  def process_response
    case @user_count
    when 1 then handle_icebreaker
    when 2..5 then handle_technical_question
    when 6 then handle_last_technical_question
    when 7..8 then handle_behavioral_question
    when 9 then handle_last_behavioral_question
    end
  end

  # First user message — respond to icebreaker + ask first technical question
  # ask() already creates and broadcasts the message — no need for save_assistant_message
  def handle_icebreaker
    ask(@message.content)
    ask_fresh("Agora faça a primeira pergunta técnica sobre #{TECHNICAL_TOPICS.first}. #{QUESTION_FORMAT}")
  end

  # Technical questions 2 to 5 — give feedback + ask next technical question
  def handle_technical_question
    ask(ask_feedback_technical_prompt)
    ask("Agora faça a próxima pergunta técnica. #{QUESTION_FORMAT}")
  end

  # Last technical question (6th user message) — give feedback + ask first behavioral question
  def handle_last_technical_question
    ask(ask_feedback_technical_prompt)
    ask("Agora faça a primeira pergunta comportamental relacionada com a vaga de #{@job.job_title}. #{QUESTION_FORMAT}")
  end

  # Behavioral questions 1 and 2 — give feedback + ask next behavioral question
  def handle_behavioral_question
    ask(ask_feedback_behavioral_prompt)
    ask("Agora faça a próxima pergunta comportamental relacionada com a vaga de #{@job.job_title}. #{QUESTION_FORMAT}")
  end

  # Last behavioral question (9th user message) — give feedback + end interview + final feedback
  def handle_last_behavioral_question
    ask(ask_feedback_behavioral_prompt)
    # Fixed message — not streamed, just created directly
    save_assistant_message("A entrevista terminou! 🎉")
    ask("Com base em todas as respostas do candidato às 5 perguntas técnicas e 3 perguntas comportamentais, dê um feedback geral caloroso e encorajador. Destaca os pontos fortes e uma sugestão de melhoria. Máximo 4 linhas.")
  end

  # Ask the LLM and stream the response chunk by chunk via Action Cable
  # Creates an empty message first, then fills it progressively in the browser
  def ask(prompt)
    @assistant_message = @chat.messages.create(role: "assistant", content: "")

    @ruby_llm_chat.with_instructions(instructions).ask(prompt) do |chunk|
      next if chunk.content.blank?
      @assistant_message.content += chunk.content
      broadcast_replace(@assistant_message)
    end

    # Save the final complete content to the database
    @assistant_message.update(content: @assistant_message.content)
    @assistant_message.content
  end

  # Same as ask but with a fresh LLM instance (no conversation history)
  # Used for the first technical question to avoid context contamination
  def ask_fresh(prompt)
    @assistant_message = @chat.messages.create(role: "assistant", content: "")

    RubyLLM.chat(model: "gpt-4o-mini").with_instructions(instructions).ask(prompt) do |chunk|
      next if chunk.content.blank?
      @assistant_message.content += chunk.content
      broadcast_replace(@assistant_message)
    end

    @assistant_message.update(content: @assistant_message.content)
    @assistant_message.content
  end

  # Returns the prompt string for technical feedback — used by ask()
  def ask_feedback_technical_prompt
    "A resposta do candidato foi '#{@message.content}'.
    Se estiver correta: parabenize de forma calorosa e breve (1 linha).
    Se estiver incorreta: corrija de forma calorosa e encorajadora. Explique a resposta correta em máximo 1 linha."
  end

  # Returns the prompt string for behavioral feedback — used by ask()
  def ask_feedback_behavioral_prompt
    "O candidato respondeu '#{@message.content}'. Dê um feedback curto, caloroso e encorajador. Máximo 1 linha."
  end

  # Save a fixed message (not streamed) — only used for "A entrevista terminou! 🎉"
  def save_assistant_message(content)
    @chat.messages.create(role: "assistant", content: content)
  end

  # Push the updated message HTML to the browser via Action Cable in real time
  # Replaces the div with id="message_42" with the new content
  def broadcast_replace(message)
    Turbo::StreamsChannel.broadcast_replace_to(
      @chat,
      target: helpers.dom_id(message),
      partial: "messages/message",
      locals: { message: message }
    )
  end

  # Context about the job and the mandatory question sequence
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
    - Respostas livres e abertas
    - Não há certo nem errado
    - Dê um feedback curto e caloroso após cada resposta comportamental

    TOTAL: 8 perguntas. Não repita perguntas. Não salte nenhuma."
  end

  # Combine system prompt and job context into full instructions
  def instructions
    [SYSTEM_PROMPT, job_context].compact.join("\n\n")
  end

  # Load the last 10 messages into the LLM conversation history
  # Skip blank messages (created during streaming but not yet filled)
  def build_conversation_history
    @chat.messages.last(10).each do |message|
      next if message.content.blank?
      @ruby_llm_chat.add_message(role: message.role, content: message.content)
    end
  end
end
