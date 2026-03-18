class MessagesController < ApplicationController
  SYSTEM_PROMPT = <<~PROMPT
    ## Persona
    Você é Chloé 2.0, entrevistadora do Le Wagon.
    Responda SEMPRE em português do Brasil.
    Seja como uma entrevistadora real — natural, direta e humana.

    ## Tom
    - Conversacional e fluido, como numa entrevista de verdade
    - Feedback breve e direto — sem discursos
    - Honesta mas gentil quando a resposta estiver errada
    - Nunca use frases vazias como "boa tentativa" sem explicar o porquê

    ## Regras OBRIGATÓRIAS
    - SEMPRE uma mensagem por vez
    - NUNCA coloque feedback e pergunta na mesma mensagem
    - NUNCA use labels como "Feedback:", "Pergunta:", "Pergunta 1/8" ou qualquer numeração
    - NUNCA numere as perguntas
    - Escreva diretamente, como numa conversa natural

    ## Formato
    - Perguntas: curtas e diretas, máximo 2 linhas
    - Feedback durante a entrevista: máximo 2 linhas, natural e humano
    - Feedback final: detalhado e estruturado
  PROMPT

  TECHNICAL_TOPICS = ["Ruby on Rails", "JavaScript", "SQL", "HTML", "CSS"].freeze

  QUESTION_FORMAT = "Faça uma pergunta curta e direta, como numa entrevista real. Máximo 2 linhas. Sem opções A/B/C."

  BEHAVIORAL_QUESTIONS_POOL = [
    "Fale um pouco sobre você com foco na sua trajetória profissional e técnica.",
    "Por que você quer trabalhar nessa área e nessa vaga especificamente?",
    "Conte sobre um projeto que você desenvolveu e qual foi o seu papel nele.",
    "Como você lida quando recebe um feedback negativo sobre o seu trabalho?",
    "Já tiveste um conflito com alguém no time? O que fizeste para resolver?",
    "Descreve um desafio técnico que enfrentaste e como resolveste.",
    "Como você aprende novas tecnologias? Tens algum método ou rotina?",
    "Conta sobre um momento em que trabalhaste sob pressão, deadline apertado ou entrega difícil.",
    "Já trabalhou em equipe? Como foi essa experiência?",
    "Conta sobre um erro ou bug que cometeste e o que aprendeste com ele.",
    "Como você organiza suas tarefas e prioriza o que é mais urgente?"
  ].freeze

  def create
    @job = Job.find(params[:job_id])
    @chat = current_user.chats.find(params[:chat_id])
    @message = Message.new(role: "user", content: params[:message][:content], chat: @chat)

    if @message.save
      @ruby_llm_chat = RubyLLM.chat(model: "gpt-4o-mini")
      @user_count = @chat.messages.where(role: "user").count
      build_conversation_history unless @user_count == 1

      if @user_count == 1
        @chat.update(behavioral_questions: BEHAVIORAL_QUESTIONS_POOL.sample(3).to_json)
      end
      @behavioral_questions = @chat.behavioral_questions.present? ? JSON.parse(@chat.behavioral_questions) : BEHAVIORAL_QUESTIONS_POOL.sample(3)

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
    ask("O candidato disse: '#{@message.content}'.
    Responde de forma calorosa e simpática. Máximo 1 linha.
    NÃO faças nenhuma pergunta. NÃO introduzas o próximo passo.")
    ask_fresh("Faça a primeira pergunta técnica sobre #{TECHNICAL_TOPICS.first} para a vaga de #{@job.job_title}. #{QUESTION_FORMAT}")
  end

  def handle_technical_question
    topic_index = @user_count - 2
    next_topic = TECHNICAL_TOPICS[topic_index] || TECHNICAL_TOPICS.last
    ask(feedback_technical_prompt)
    ask("Faça uma pergunta técnica sobre #{next_topic} para a vaga de #{@job.job_title}. #{QUESTION_FORMAT}")
  end

  def handle_last_technical_question
    ask(feedback_technical_prompt)
    ask("Faça esta pergunta exatamente como está, sem alterar nada: \"#{@behavioral_questions[0]}\"")
  end

  def handle_behavioral_question
    behavioral_index = @user_count - 6
    next_question = @behavioral_questions[behavioral_index]
    ask(feedback_behavioral_prompt)
    ask("Faça esta pergunta exatamente como está, sem alterar nada: \"#{next_question}\"")
  end

  def handle_last_behavioral_question
    ask(feedback_behavioral_prompt)
    save_assistant_message("A entrevista terminou! 🎉 Um momento, vou preparar o teu feedback final e score...")
    ask(score_prompt)
  end

  def feedback_technical_prompt
    "A resposta do candidato foi: '#{@message.content}'.

    Responde como uma entrevistadora real — máximo 2 linhas:
    - Se correta: confirma brevemente o que estava bem
    - Se parcialmente correta: reconhece o acerto e aponta em 1 frase o que faltou
    - Se incorreta: corrige de forma direta e gentil, explica a resposta certa em 1 frase

    Sem discursos. Natural e humano.
    NÃO faças nenhuma pergunta. NÃO introduzas a próxima."
  end

  def feedback_behavioral_prompt
    "O candidato respondeu: '#{@message.content}'.

    Dá um feedback breve como uma entrevistadora real — máximo 2 linhas:
    - Se concreta e bem estruturada: confirma brevemente o que foi bem
    - Se vaga: diz gentilmente o que faltou em 1 frase

    NÃO faças nenhuma pergunta. NÃO introduzas a próxima."
  end

  def score_prompt
    "Com base em TODAS as respostas do candidato, faz a avaliação final.

    REGRAS DO SCORE:
    - Resposta vazia ou 'não sei': vale 0 pontos
    - Resposta muito vaga ou incorreta: vale 1 ponto
    - Resposta parcialmente correta: vale 1.5 pontos
    - Resposta correta e completa: vale 2 pontos
    - São 5 perguntas técnicas + 3 comportamentais = 8 no total
    - Faz a média e converte para escala de 0 a 10
    - Se o candidato respondeu 'não sei' na maioria, o score DEVE ser abaixo de 3

    Usa EXATAMENTE este formato:

    Score: X/10

    Pontos fortes:
    - [ponto concreto baseado nas respostas reais]

    A melhorar:
    - [sugestão prática e específica]
    - [sugestão prática e específica]

    [frase de encorajamento honesta]"
  end

  def ask(prompt)
    @assistant_message = @chat.messages.create(role: "assistant", content: "")
    full_content = ""

    @ruby_llm_chat.with_instructions(instructions).ask(prompt) do |chunk|
      next if chunk.content.blank?
      full_content += chunk.content
      @assistant_message.content = full_content
      broadcast_replace(@assistant_message)
    end

    sleep(0.2)
    @assistant_message.update!(content: full_content)
    broadcast_replace(@assistant_message)
    full_content
  end

  def ask_fresh(prompt)
    @assistant_message = @chat.messages.create(role: "assistant", content: "")
    full_content = ""

    RubyLLM.chat(model: "gpt-4o-mini").with_instructions(instructions).ask(prompt) do |chunk|
      next if chunk.content.blank?
      full_content += chunk.content
      @assistant_message.content = full_content
      broadcast_replace(@assistant_message)
    end

    sleep(0.2)
    @assistant_message.update!(content: full_content)
    broadcast_replace(@assistant_message)
    full_content
  end

  def save_assistant_message(content)
    @chat.messages.create(role: "assistant", content: content)
  end

  def broadcast_replace(message)
    Turbo::StreamsChannel.broadcast_replace_to(
      @chat,
      target: helpers.dom_id(message),
      partial: "messages/message",
      locals: { message: message }
    )
  end

  def job_context
    "A vaga para a qual o candidato está se preparando é: #{@job.job_title}. #{@job.job_description}

    SEQUÊNCIA OBRIGATÓRIA:

    PARTE 1 — 5 perguntas técnicas (uma por vez):
    1. Ruby on Rails
    2. JavaScript
    3. SQL
    4. HTML
    5. CSS

    PARTE 2 — 3 perguntas comportamentais (uma por vez), nesta ordem exata:
    1. #{@behavioral_questions&.dig(0)}
    2. #{@behavioral_questions&.dig(1)}
    3. #{@behavioral_questions&.dig(2)}

    TOTAL: 8 perguntas. Não repitas. Não saltes nenhuma."
  end

  def instructions
    [SYSTEM_PROMPT, job_context].compact.join("\n\n")
  end

  def build_conversation_history
    @chat.messages.last(10).each do |message|
      next if message.content.blank?
      @ruby_llm_chat.add_message(role: message.role, content: message.content)
    end
  end
end
