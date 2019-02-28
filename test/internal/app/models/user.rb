class User < ActiveRecord::Base
  has_one_attached :avatar
  attached_encrypted :avatar, key: SecureRandom.random_bytes(32)

  has_many_attached :avatars
  attached_encrypted :avatars, key: SecureRandom.random_bytes(32)

  has_one_attached :image
  has_many_attached :images

  mount_uploader :document, DocumentUploader

  attr_encrypted :email, encryptor: Lockbox::Encryptor, key: SecureRandom.random_bytes(32), previous_versions: [{key: SecureRandom.random_bytes(32)}]
  attr_accessor :encrypted_email_iv

  key_pair = Lockbox.generate_key_pair
  attr_encrypted :phone, encryptor: Lockbox::Encryptor, algorithm: "hybrid", encryption_key: key_pair[:encryption_key], decryption_key: key_pair[:decryption_key]
  attr_accessor :encrypted_phone_iv
end
