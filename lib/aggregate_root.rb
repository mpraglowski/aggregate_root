require 'active_support/inflector'
require 'aggregate_root/version'

class AggregateRoot < Module
  def initialize(strategy: DefaultApplyStrategy.new, event_store: nil)
    @strategy = strategy
    @event_store = event_store
    define_methods
    freeze
  end

  private
  class DefaultApplyStrategy
    def call(aggregate, event)
      event_name_processed = event.class.name.demodulize.underscore
      aggregate.method("apply_#{event_name_processed}").call(event)
    end
  end

  class Configuration
    attr_accessor :default_event_store
  end

  def included(descendant)
    super
    descendant.include Methods
  end

  def define_methods
    define_apply_strategy
    define_default_event_store
  end

  def define_apply_strategy
    strategy = @strategy
    define_method(:apply_strategy) do | |
      strategy
    end
  end

  def define_default_event_store
    event_store = @event_store
    define_method(:default_event_store) do | |
      event_store
    end
  end

  module Methods
    def apply(event)
      apply_strategy.(self, event)
      unpublished_events << event
    end

    def load(stream_name, event_store: default_event_store)
      @loaded_from_stream_name = stream_name
      events = event_store.read_stream_events_forward(stream_name)
      events.each do |event|
        apply(event)
      end
      @unpublished_events = nil
      self
    end

    def store(stream_name = loaded_from_stream_name, event_store: default_event_store)
      unpublished_events.each do |event|
        event_store.publish_event(event, stream_name: stream_name)
      end
      @unpublished_events = nil
    end

    private
    attr_reader :loaded_from_stream_name

    def unpublished_events
      @unpublished_events ||= []
    end
  end
end
