# frozen_string_literal: true

RSpec.describe Clowk::Current do
  subject(:current_clowk) do
    described_class.new(
      "sub" => "user_123",
      "email" => "user@example.com",
      "name" => "Jane Doe",
      "avatar_url" => "https://cdn.example.com/avatar.png",
      "provider" => "google",
      "instance_id" => "inst_123",
      "app_id" => "app_123"
    )
  end

  it "exposes normalized attributes" do
    expect(current_clowk.id).to eq("user_123")
    expect(current_clowk.email).to eq("user@example.com")
    expect(current_clowk.name).to eq("Jane Doe")
    expect(current_clowk.avatar_url).to eq("https://cdn.example.com/avatar.png")
    expect(current_clowk.provider).to eq("google")
    expect(current_clowk.instance_id).to eq("inst_123")
    expect(current_clowk.app_id).to eq("app_123")
  end

  it "returns a hash with id normalized from sub" do
    expect(current_clowk.to_h).to include(id: "user_123", email: "user@example.com")
  end
end