class Lockbox
  class Box
    def initialize(key, algorithm: nil)
      # decode hex key
      if key.encoding != Encoding::BINARY && key =~ /\A[0-9a-f]{64}\z/i
        key = [key].pack("H*")
      end

      algorithm ||= "aes-gcm"

      case algorithm
      when "aes-gcm"
        require "lockbox/aes_gcm"
        @box = AES_GCM.new(key)
      when "xchacha20"
        require "rbnacl"
        @box = RbNaCl::AEAD::XChaCha20Poly1305IETF.new(key)
      else
        raise ArgumentError, "Unknown algorithm: #{algorithm}"
      end
    end

    def encrypt(message, associated_data: nil)
      nonce = generate_nonce
      ciphertext = @box.encrypt(nonce, message, associated_data)
      nonce + ciphertext
    end

    def decrypt(ciphertext, associated_data: nil)
      nonce, ciphertext = extract_nonce(ciphertext)
      @box.decrypt(nonce, ciphertext, associated_data)
    end

    # protect key for xchacha20
    def inspect
      to_s
    end

    private

    def nonce_bytes
      @box.nonce_bytes
    end

    def generate_nonce
      SecureRandom.random_bytes(nonce_bytes)
    end

    def extract_nonce(bytes)
      nonce = bytes.slice(0, nonce_bytes)
      [nonce, bytes.slice(nonce_bytes..-1)]
    end
  end
end
