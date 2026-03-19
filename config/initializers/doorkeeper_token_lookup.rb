# frozen_string_literal: true

# Adiciona métodos personalizados para encontrar tokens em cookies
module Doorkeeper
  module OAuth
    class Token
      module Methods
        # Método para obter o token do cookie de acesso
        # Pode ser chamado porque adicionamos :from_cookie aos access_token_methods
        def from_cookie(request)
          # Tentativa de encontrar o token em diferentes cookies
          cookies = request.cookies
          return nil unless cookies
          
          # Se não encontrar, procura pelo refresh token se estiver configurado para aceitar
          # Isso é útil para a validação direta de tokens (sem necessidade de extraí-los do cookie)
          if ENV['ACCEPT_REFRESH_TOKEN_AS_ACCESS_TOKEN'] == 'true'
            return cookies['_evo_rt'] if cookies['_evo_rt'].present?
            return cookies['refresh_token'] if cookies['refresh_token'].present?
          end
          
          nil
        end
      end
    end
  end
end
