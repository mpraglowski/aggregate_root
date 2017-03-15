require 'spec_helper'

describe AggregateRoot do
  let(:event_store) { RubyEventStore::Client.new(repository: RubyEventStore::InMemoryRepository.new) }

  module Orders
    module Events
      OrderCreated = Class.new(RubyEventStore::Event)
      OrderExpired = Class.new(RubyEventStore::Event)
    end
  end

  class Order
    include AggregateRoot.new(event_store: event_store)

    def initialize
      @status = :draft
    end

    def expected_events
      unpublished_events
    end

    attr_accessor :status
    private

    def apply_order_created(event)
      @status = :created
    end

    def apply_order_expired(event)
      @status = :expired
    end
  end

  class OrderWithoutEventStoreAssigned
    include AggregateRoot.new

    def initialize
      @status = :draft
    end

    def expected_events
      unpublished_events
    end

    attr_accessor :status
    private

    def apply_order_created(event)
      @status = :created
    end

    def apply_order_expired(event)
      @status = :expired
    end
  end

  class CustomOrderApplyStrategy
    def call(aggregate, event)
      {
        Orders::Events::OrderCreated => aggregate.method(:custom_created),
        Orders::Events::OrderExpired => aggregate.method(:custom_expired),
      }.fetch(event.class, ->(ev) {}).call(event)
    end
  end

  class OrderWithCustomStrategy
    include AggregateRoot.new(event_store: event_store, strategy: CustomOrderApplyStrategy.new)

    def initialize
      @status = :draft
    end

    def expected_events
      unpublished_events
    end

    attr_accessor :status
    private

    def custom_created(event)
      @status = :created
    end

    def custom_expired(event)
      @status = :expired
    end
  end

  it "should have ability to apply event on itself" do
    order = Order.new
    order_created = Orders::Events::OrderCreated.new

    expect(order).to receive(:apply_order_created).with(order_created).and_call_original
    order.apply(order_created)
    expect(order.status).to eq :created
    expect(order.expected_events).to eq([order_created])
  end

  it "brand new aggregate does not have any unpublished events" do
    order = Order.new
    expect(order.expected_events).to be_empty
  end

  it "should have no unpublished events when loaded" do
    stream = "any-order-stream"
    order_created = Orders::Events::OrderCreated.new
    event_store.publish_event(order_created, stream_name: stream)

    order = Order.new.load(stream, event_store: event_store)
    expect(order.status).to eq :created
    expect(order.expected_events).to be_empty
  end

  it "should publish all unpublished events on store" do
    stream = "any-order-stream"
    order_created = Orders::Events::OrderCreated.new
    order_expired = Orders::Events::OrderExpired.new

    order = Order.new
    order.apply(order_created)
    order.apply(order_expired)
    expect(event_store).to receive(:publish_event).with(order_created, stream_name: stream).and_call_original
    expect(event_store).to receive(:publish_event).with(order_expired, stream_name: stream).and_call_original
    order.store(stream, event_store: event_store)
    expect(order.expected_events).to be_empty
  end

  it "should work with provided event_store" do
    stream = "any-order-stream"
    order = OrderWithoutEventStoreAssigned.new.load(stream, event_store: event_store)
    order_created = Orders::Events::OrderCreated.new
    order.apply(order_created)
    order.store(stream, event_store: event_store)

    expect(event_store.read_stream_events_forward(stream)).to eq [order_created]

    restored_order = Order.new.load(stream, event_store: event_store)
    expect(restored_order.status).to eq :created
    order_expired = Orders::Events::OrderExpired.new
    restored_order.apply(order_expired)
    restored_order.store(stream, event_store: event_store)

    expect(event_store.read_stream_events_forward(stream)).to eq [order_created, order_expired]

    restored_again_order = Order.new.load(stream, event_store: event_store)
    expect(restored_again_order.status).to eq :expired
  end

  it "should use default client if event_store not provided" do
    stream = "any-order-stream"
    order = Order.new.load(stream)
    order_created = Orders::Events::OrderCreated.new
    order.apply(order_created)
    order.store(stream)

    expect(event_store.read_stream_events_forward(stream)).to eq [order_created]

    restored_order = Order.new.load(stream)
    expect(restored_order.status).to eq :created
    order_expired = Orders::Events::OrderExpired.new
    restored_order.apply(order_expired)
    restored_order.store(stream)

    expect(event_store.read_stream_events_forward(stream)).to eq [order_created, order_expired]

    restored_again_order = Order.new.load(stream)
    expect(restored_again_order.status).to eq :expired
  end

  it "if loaded from some stream should store to the same stream is no other stream specified" do
    stream = "any-order-stream"
    order = Order.new.load(stream)
    order_created = Orders::Events::OrderCreated.new
    order.apply(order_created)
    order.store

    expect(event_store.read_stream_events_forward(stream)).to eq [order_created]
  end

  it "should receive a method call based on a default apply strategy" do
    order = Order.new
    order_created = Orders::Events::OrderCreated.new

    order.apply(order_created)
    expect(order.status).to eq :created
  end

  it "should receive a method call based on a custom strategy" do
    order = OrderWithCustomStrategy.new
    order_created = Orders::Events::OrderCreated.new

    order.apply(order_created)
    expect(order.status).to eq :created
  end
end
