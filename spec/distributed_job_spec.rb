# frozen_string_literal: true

require File.expand_path('spec_helper', __dir__)

RSpec.describe DistributedJob do
  let(:distributed_job) { described_class.new(redis: Redis.new, token: SecureRandom.hex, ttl: 100) }

  let(:state_ttl) { distributed_job.redis.ttl("distributed_jobs:#{distributed_job.token}:state") }
  let(:parts_ttl) { distributed_job.redis.ttl("distributed_jobs:#{distributed_job.token}:parts") }

  describe '#push' do
    it 'increments count by 1' do
      expect(distributed_job.count).to eq(0)
      distributed_job.send(:push, 'part')
      expect(distributed_job.count).to eq(1)
    end

    it 'does not increment count when the part is already present' do
      expect(distributed_job.count).to eq(0)
      distributed_job.send(:push, 'part')
      distributed_job.send(:push, 'part')
      expect(distributed_job.count).to eq(1)
    end

    it 'increments total by 1' do
      expect(distributed_job.total).to eq(0)
      distributed_job.send(:push, 'part')
      expect(distributed_job.total).to eq(1)
    end

    it 'does not increment total when the part is already present' do
      expect(distributed_job.total).to eq(0)
      distributed_job.send(:push, 'part')
      distributed_job.send(:push, 'part')
      expect(distributed_job.total).to eq(1)
    end

    it 'adds the part' do
      distributed_job.send(:push, 'part1')
      distributed_job.send(:push, 'part2')

      expect(distributed_job.open_parts.to_set).to eq(%w[part1 part2].to_set)
    end

    it 'sets an expiry on the keys' do
      distributed_job.send(:push, 'part')

      expect(state_ttl.between?(0, 100)).to eq(true)
      expect(parts_ttl.between?(0, 100)).to eq(true)
    end
  end

  describe '#push_each' do
    let(:items) { %w[item1 item2 item3] }

    it 'pushes each part where the part id is its index' do
      distributed_job.push_each(items) do
        # nothing
      end

      expect(distributed_job.open_parts.to_set).to eq(%w[0 1 2].to_set)
    end

    it 'pushes each part before the item is yielded' do
      distributed_job.push_each(items) do |_, part|
        expect(distributed_job.open_parts.to_set).to include(part)
      end
    end

    it 'yields each element with its part id' do
      res = []

      distributed_job.push_each(items) do |item, part|
        res << [item, part]
      end

      expect(res).to eq([%w[item1 0], %w[item2 1], %w[item3 2]])
    end

    it 'closes the job right before the last element is yielded' do
      distributed_job.push_each(items) do |item, _|
        if item == items.last
          expect(distributed_job.send(:closed?)).to eq(true)
        else
          expect(distributed_job.send(:closed?)).to eq(false)
        end
      end
    end
  end

  describe '#done' do
    it 'decrements count by -1' do
      distributed_job.send(:push, 'part')
      distributed_job.done('part')

      expect(distributed_job.count).to eq(0)
    end

    it 'does not decrement the count if the part is unknown' do
      distributed_job.send(:push, 'part')
      distributed_job.done('unknown')

      expect(distributed_job.count).to eq(1)
    end

    it 'removes the part' do
      distributed_job.send(:push, 'part1')
      distributed_job.send(:push, 'part2')
      distributed_job.done('part1')

      expect(distributed_job.open_parts.to_set).to eq(['part2'].to_set)
    end

    it 'returns true when the last part is done and the job is closed' do
      distributed_job.send(:push, 'part')
      distributed_job.send(:close)

      expect(distributed_job.done('part')).to eq(true)
    end

    it 'return false when the currently last part is done but the job is not closed' do
      distributed_job.send(:push, 'part')

      expect(distributed_job.done('part')).to eq(false)
    end

    it 'returns false when there are more parts left' do
      distributed_job.send(:push, 'part1')
      distributed_job.send(:push, 'part2')

      expect(distributed_job.done('part1')).to eq(false)
    end

    it 'returns false when there is no part' do
      expect(distributed_job.done('part')).to eq(false)
    end

    it 'sets an expiry on the keys' do
      distributed_job.send(:push, 'part1')
      distributed_job.send(:push, 'part2')
      distributed_job.done('part1')

      expect(state_ttl.between?(0, 100)).to eq(true)
      expect(parts_ttl.between?(0, 100)).to eq(true)
    end
  end

  describe '#stop' do
    it 'marks the job as stopped' do
      expect(distributed_job.stopped?).to eq(false)
      distributed_job.stop
      expect(distributed_job.stopped?).to eq(true)
    end

    it 'sets an expiry on the keys' do
      distributed_job.send(:push, 'part')
      distributed_job.stop

      expect(state_ttl.between?(0, 100)).to eq(true)
      expect(parts_ttl.between?(0, 100)).to eq(true)
    end
  end

  describe '#close' do
    it 'marks the job as closed' do
      expect(distributed_job.send(:closed?)).to eq(false)
      distributed_job.send(:close)
      expect(distributed_job.send(:closed?)).to eq(true)
    end

    it 'sets an expiry on the keys' do
      distributed_job.send(:push, 'part')
      distributed_job.send(:close)

      expect(state_ttl.between?(0, 100)).to eq(true)
      expect(parts_ttl.between?(0, 100)).to eq(true)
    end
  end

  describe '#total' do
    it 'returns the total' do
      expect(distributed_job.total).to eq(0)
      distributed_job.send(:push, 'part1')
      distributed_job.send(:push, 'part2')
      expect(distributed_job.total).to eq(2)
    end
  end
end
