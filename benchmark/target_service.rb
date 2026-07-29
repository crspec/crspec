# frozen_string_literal: true

require "digest"

class UserService
  def self.process_user(id, name, email)
    # Simulate non-blocking I/O query (e.g. database lease / HTTP call)
    sleep 0.001
    token = Digest::SHA256.hexdigest("#{id}-#{name}-#{email}")
    { id: id, name: name, email: email, token: token, valid: true }
  end
end
