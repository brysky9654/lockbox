module Lockbox
  class Migrator
    def initialize(relation, batch_size:)
      @relation = relation
      @transaction = @relation.respond_to?(:transaction)
      @batch_size = batch_size
    end

    def model
      @model ||= @relation
    end

    def rotate(attributes:)
      fields = {}
      attributes.each do |a|
        # use key instad of v[:attribute] to make it more intuitive when migrating: true
        field = model.lockbox_attributes[a]
        raise ArgumentError, "Bad attribute: #{a}" unless field
        fields[a] = field
      end

      perform(fields: fields)
    end

    # TODO add attributes option
    def migrate(restart:)
      fields = model.lockbox_attributes.select { |k, v| v[:migrating] }

      blind_indexes = model.respond_to?(:blind_indexes) ? model.blind_indexes.select { |k, v| v[:migrating] } : {}

      perform(fields: fields, blind_indexes: blind_indexes, restart: restart)
    end

    private

    def perform(fields:, blind_indexes: [], restart: true)
      base_relation = @relation

      # remove true condition in 0.4.0
      if true || (defined?(ActiveRecord::Base) && base_relation.is_a?(ActiveRecord::Base))
        base_relation = base_relation.unscoped
      end

      relation = base_relation

      unless restart
        attributes = fields.map { |_, v| v[:encrypted_attribute] }
        attributes += blind_indexes.map { |_, v| v[:bidx_attribute] }

        if defined?(ActiveRecord::Relation) && base_relation.is_a?(ActiveRecord::Relation)
          attributes.each_with_index do |attribute, i|
            relation =
              if i == 0
                relation.where(attribute => nil)
              else
                relation.or(base_relation.where(attribute => nil))
              end
          end
        else
          relation = relation.or(attributes.map { |a| {a => nil} })
        end
      end

      each_batch(relation) do |records|
        migrate_records(records, fields: fields, blind_indexes: blind_indexes, restart: restart)
      end
    end

    def each_batch(relation)
      if relation.respond_to?(:find_in_batches)
        relation.find_in_batches(batch_size: @batch_size) do |records|
          yield records
        end
      else
        # https://github.com/karmi/tire/blob/master/lib/tire/model/import.rb
        # use cursor for Mongoid
        records = []
        relation.all.each do |record|
          records << record
          if records.length == @batch_size
            yield records
            records = []
          end
        end
        yield records if records.any?
      end
    end

    def migrate_records(records, fields:, blind_indexes:, restart:)
      # do computation outside of transaction
      # especially expensive blind index computation
      records.each do |record|
        fields.each do |k, v|
          record.send("#{v[:attribute]}=", record.send(k)) if restart || !record.send(v[:encrypted_attribute])
        end
        blind_indexes.each do |k, v|
          record.send("compute_#{k}_bidx") if restart || !record.send(v[:bidx_attribute])
        end
      end

      records.select! { |r| r.changed? }

      with_transaction do
        records.each do |record|
          record.save!(validate: false)
        end
      end
    end

    def with_transaction
      if @transaction
        @relation.transaction do
          yield
        end
      else
        yield
      end
    end
  end
end
