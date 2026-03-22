# frozen_string_literal: true

Clowk::Engine.routes.draw do
  get '/sign_in', to: 'sessions#new', as: :sign_in
  get '/sign_up', to: 'sessions#sign_up', as: :sign_up
  match '/sign_out', to: 'sessions#destroy', via: %i(get delete), as: :sign_out
  get '/oauth/callback', to: 'callbacks#show', as: :auth_callback
end
