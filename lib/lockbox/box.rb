require "securerandom"

class Lockbox
  class Box
    def initialize(key: nil, algorithm: nil, encryption_key: nil, decryption_key: nil)
      raise ArgumentError, "Cannot pass both key and public/private key" if key && (encryption_key || decryption_key)

      key = decode_key(key) if key
      encryption_key = decode_key(encryption_key) if encryption_key
      decryption_key = decode_key(decryption_key) if decryption_key

      algorithm ||= "aes-gcm"

      case algorithm
      when "aes-gcm"
        raise ArgumentError, "Missing key" unless key
        require "lockbox/aes_gcm"
        @box = AES_GCM.new(key)
      when "xchacha20"
        raise ArgumentError, "Missing key" unless key
        require "rbnacl"
        @box = RbNaCl::AEAD::XChaCha20Poly1305IETF.new(key)
      when "hybrid"
        raise ArgumentError, "Missing key" unless encryption_key || decryption_key
        require "rbnacl"
        @encryption_box = RbNaCl::Boxes::Curve25519XSalsa20Poly1305.new(encryption_key.slice(0, 32), encryption_key.slice(32..-1)) if encryption_key
        @decryption_box = RbNaCl::Boxes::Curve25519XSalsa20Poly1305.new(decryption_key.slice(32..-1), decryption_key.slice(0, 32)) if decryption_key
      else
        raise ArgumentError, "Unknown algorithm: #{algorithm}"
      end

      @algorithm = algorithm
    end

    def encrypt(message, associated_data: nil)
      if @algorithm == "hybrid"
        raise ArgumentError, "No public key set" unless @encryption_box
        raise ArgumentError, "Associated data not supported with this algorithm" if associated_data
        nonce = generate_nonce(@encryption_box)
        ciphertext = @encryption_box.encrypt(nonce, message)
      else
        nonce = generate_nonce(@box)
        ciphertext = @box.encrypt(nonce, message, associated_data)
      end
      nonce + ciphertext
    end

    def decrypt(ciphertext, associated_data: nil)
      if @algorithm == "hybrid"
        raise ArgumentError, "No private key set" unless @decryption_box
        raise ArgumentError, "Associated data not supported with this algorithm" if associated_data
        nonce, ciphertext = extract_nonce(@decryption_box, ciphertext)
        @decryption_box.decrypt(nonce, ciphertext)
      else
        nonce, ciphertext = extract_nonce(@box, ciphertext)
        @box.decrypt(nonce, ciphertext, associated_data)
      end
    end

    # protect key for xchacha20 and hybrid
    def inspect
      to_s
    end

    private

    def generate_nonce(box)
      SecureRandom.random_bytes(box.nonce_bytes)
    end

    def extract_nonce(box, bytes)
      nonce_bytes = box.nonce_bytes
      nonce = bytes.slice(0, nonce_bytes)
      [nonce, bytes.slice(nonce_bytes..-1)]
    end

    # decode hex key
    def decode_key(key)
      if key.encoding != Encoding::BINARY && key =~ /\A[0-9a-f]{64,128}\z/i
        key = [key].pack("H*")
      end
      key
    end
  end
end
