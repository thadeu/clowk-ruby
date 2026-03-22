# frozen_string_literal: true

ClowkSpecApp.routes.draw do
  mount Clowk::Engine => "/clowk"

  get "/", to: ->(_env) { [200, { "Content-Type" => "text/plain" }, ["root"]] }
  get "/dashboard", to: ->(_env) { [200, { "Content-Type" => "text/plain" }, ["dashboard"]] }
  get "/after_sign_in", to: ->(_env) { [200, { "Content-Type" => "text/plain" }, ["after_sign_in"]] }
  get "/after_sign_out", to: ->(_env) { [200, { "Content-Type" => "text/plain" }, ["after_sign_out"]] }
end