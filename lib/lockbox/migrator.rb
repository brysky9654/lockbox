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
        # use key instead of v[:attribute] to make it more intuitive when migrating: true
        field = model.lockbox_attributes[a]
        raise ArgumentError, "Bad attribute: #{a}" unless field
        fields[a] = field
      end

      perform(fields: fields, rotate: true)
    end

    # TODO add attributes option
    def migrate(restart:)
      fields = model.lockbox_attributes.select { |k, v| v[:migrating] }

      # need blind indexes for building relation
      blind_indexes = model.respond_to?(:blind_indexes) ? model.blind_indexes.select { |k, v| v[:migrating] } : {}

      perform(fields: fields, blind_indexes: blind_indexes, restart: restart)
    end

    private

    def perform(fields:, blind_indexes: [], restart: true, rotate: false)
      relation = @relation

      # unscope if passed a model
      unless ar_relation?(relation) || mongoid_relation?(relation)
        relation = relation.unscoped
      else
        # TODO remove in 0.4.0
        relation = relation.unscoped
      end

      # convert from possible class to ActiveRecord::Relation or Mongoid::Criteria
      relation = relation.all

      unless restart
        attributes = fields.map { |_, v| v[:encrypted_attribute] }
        attributes += blind_indexes.map { |_, v| v[:bidx_attribute] }

        if ar_relation?(relation)
          base_relation = relation.unscoped
          or_relation = relation.unscoped

          attributes.each_with_index do |attribute, i|
            or_relation =
              if i == 0
                base_relation.where(attribute => nil)
              else
                or_relation.or(base_relation.where(attribute => nil))
              end
          end

          relation = relation.merge(or_relation)
        else
          relation = relation.or(attributes.map { |a| {a => nil} })
        end
      end

      each_batch(relation) do |records|
        migrate_records(records, fields: fields, blind_indexes: blind_indexes, restart: restart, rotate: rotate)
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

    def migrate_records(records, fields:, blind_indexes:, restart:, rotate:)
      # do computation outside of transaction
      # especially expensive blind index computation
      if rotate
        records.each do |record|
          fields.each do |k, v|
            # update encrypted attribute directly to skip blind index computation
            record.send("lockbox_direct_#{k}=", record.send(k))
          end
        end
      else
        records.each do |record|
          if restart
            fields.each do |k, v|
              record.send("#{v[:encrypted_attribute]}=", nil)
            end

            blind_indexes.each do |k, v|
              record.send("#{v[:bidx_attribute]}=", nil)
            end
          end

          fields.each do |k, v|
            record.send("#{v[:attribute]}=", record.send(k)) unless record.send(v[:encrypted_attribute])
          end

          # with Blind Index 2.0, bidx_attribute should be already set for each record
          blind_indexes.each do |k, v|
            record.send("compute_#{k}_bidx") unless record.send(v[:bidx_attribute])
          end
        end
      end

      # don't need to save records that went from nil => nil
      records.select! { |r| r.changed? }

      if records.any?
        with_transaction do
          records.each do |record|
            record.save!(validate: false)
          end
        end
      end
    end

    def ar_relation?(relation)
      defined?(ActiveRecord::Relation) && relation.is_a?(ActiveRecord::Relation)
    end

    def mongoid_relation?(relation)
      defined?(Mongoid::Criteria) && relation.is_a?(Mongoid::Criteria)
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
