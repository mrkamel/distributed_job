# frozen_string_literal: true

require File.expand_path('../spec_helper', __dir__)

module DistributedJob
  RSpec.describe Job do
    let(:client) { Client.new(redis: redis) }
    let(:job) { described_class.new(client: client, token: SecureRandom.hex, ttl: 100) }
    let(:redis) { Redis.new }

    let(:state_ttl) { redis.ttl("distributed_jobs:#{job.token}:state") }
    let(:parts_ttl) { redis.ttl("distributed_jobs:#{job.token}:parts") }

    describe '#push' do
      it 'increments count by 1' do
        expect(job.count).to eq(0)
        job.send(:push, 'part')
        expect(job.count).to eq(1)
      end

      it 'does not increment count when the part is already present' do
        expect(job.count).to eq(0)
        job.send(:push, 'part')
        job.send(:push, 'part')
        expect(job.count).to eq(1)
      end

      it 'increments total by 1' do
        expect(job.total).to eq(0)
        job.send(:push, 'part')
        expect(job.total).to eq(1)
      end

      it 'does not increment total when the part is already present' do
        expect(job.total).to eq(0)
        job.send(:push, 'part')
        job.send(:push, 'part')
        expect(job.total).to eq(1)
      end

      it 'adds the part' do
        job.send(:push, 'part1')
        job.send(:push, 'part2')

        expect(job.open_parts.to_set).to eq(%w[part1 part2].to_set)
      end

      it 'sets an expiry on the keys' do
        job.send(:push, 'part')

        expect(state_ttl.between?(0, 100)).to eq(true)
        expect(parts_ttl.between?(0, 100)).to eq(true)
      end
    end

    describe '#push_all' do
      it 'increments the count' do
        expect(job.count).to eq(0)
        job.push_all(%w[part1 part2 part3])
        expect(job.count).to eq(3)
      end

      it 'does not increment count for duplicate items' do
        expect(job.count).to eq(0)
        job.push_all(%w[part1 part2 part2 part3])
        expect(job.count).to eq(3)
      end

      it 'increments total' do
        expect(job.total).to eq(0)
        job.push_all(%w[part1 part2 part3])
        expect(job.total).to eq(3)
      end

      it 'does not increment total for duplicate items' do
        expect(job.total).to eq(0)
        job.push_all(%w[part1 part2 part2 part3])
        expect(job.total).to eq(3)
      end

      it 'adds the parts' do
        job.push_all(%w[part1 part2 part3])

        expect(job.open_parts.to_set).to eq(%w[part1 part2 part3].to_set)
      end

      it 'sets an expiry on the keys' do
        job.push_all(%w[part1 part2 part3])

        expect(state_ttl.between?(0, 100)).to eq(true)
        expect(parts_ttl.between?(0, 100)).to eq(true)
      end

      it 'closes the job' do
        job.push_all(%w[part1 part2])

        expect(job.send(:closed?)).to eq(true)
      end

      it 'raises an AlreadyClosed error when the job is already closed' do
        job.send(:close)

        expect { job.push_all(%w[part1 part2]) }.to raise_error(AlreadyClosed)
      end
    end

    describe '#push_each' do
      let(:items) { %w[item1 item2 item3] }

      it 'pushes each part where the part id is its index' do
        job.push_each(items) do
          # nothing
        end

        expect(job.open_parts.to_set).to eq(%w[0 1 2].to_set)
      end

      it 'pushes each part before the item is yielded' do
        job.push_each(items) do |_, part|
          expect(job.open_parts.to_set).to include(part)
        end
      end

      it 'yields each element with its part id' do
        res = []

        job.push_each(items) do |item, part|
          res << [item, part]
        end

        expect(res).to eq([%w[item1 0], %w[item2 1], %w[item3 2]])
      end

      it 'closes the job right before the last element is yielded' do
        job.push_each(items) do |item, _|
          if item == items.last
            expect(job.send(:closed?)).to eq(true)
          else
            expect(job.send(:closed?)).to eq(false)
          end
        end
      end

      it 'raises an AlreadyClosed error when the job is already closed' do
        job.send(:close)

        expect do
          job.push_each(%w[part1 part2]) do
            # nothing
          end
        end.to raise_error(AlreadyClosed)
      end
    end

    describe '#done' do
      it 'decrements count by -1' do
        job.send(:push, 'part')
        job.done('part')

        expect(job.count).to eq(0)
      end

      it 'does not decrement the count if the part is unknown' do
        job.send(:push, 'part')
        job.done('unknown')

        expect(job.count).to eq(1)
      end

      it 'removes the part' do
        job.send(:push, 'part1')
        job.send(:push, 'part2')
        job.done('part1')

        expect(job.open_parts.to_set).to eq(['part2'].to_set)
      end

      it 'returns true when the last part is done and the job is closed' do
        job.send(:push, 'part')
        job.send(:close)

        expect(job.done('part')).to eq(true)
      end

      it 'return false when the currently last part is done but the job is not closed' do
        job.send(:push, 'part')

        expect(job.done('part')).to eq(false)
      end

      it 'returns false when there are more parts left' do
        job.send(:push, 'part1')
        job.send(:push, 'part2')

        expect(job.done('part1')).to eq(false)
      end

      it 'returns false when there is no part' do
        expect(job.done('part')).to eq(false)
      end

      it 'sets an expiry on the keys' do
        job.send(:push, 'part1')
        job.send(:push, 'part2')
        job.done('part1')

        expect(state_ttl.between?(0, 100)).to eq(true)
        expect(parts_ttl.between?(0, 100)).to eq(true)
      end
    end

    describe '#stop' do
      it 'marks the job as stopped' do
        expect(job.stopped?).to eq(false)
        job.stop
        expect(job.stopped?).to eq(true)
      end

      it 'sets an expiry on the keys' do
        job.send(:push, 'part')
        job.stop

        expect(state_ttl.between?(0, 100)).to eq(true)
        expect(parts_ttl.between?(0, 100)).to eq(true)
      end
    end

    describe '#close' do
      it 'marks the job as closed' do
        expect(job.send(:closed?)).to eq(false)
        job.send(:close)
        expect(job.send(:closed?)).to eq(true)
      end

      it 'sets an expiry on the keys' do
        job.send(:push, 'part')
        job.send(:close)

        expect(state_ttl.between?(0, 100)).to eq(true)
        expect(parts_ttl.between?(0, 100)).to eq(true)
      end
    end

    describe '#total' do
      it 'returns the total' do
        expect(job.total).to eq(0)
        job.send(:push, 'part1')
        job.send(:push, 'part2')
        expect(job.total).to eq(2)
      end
    end

    context 'with namespace' do
      let(:client) { DistributedJob::Client.new(redis: redis, namespace: 'some_namespace') }

      it 'namespaces the keys using the specified namespace' do
        job.push_each(%w[item1 item2 item3]) do
          # nothing
        end

        expect(redis.exists?("some_namespace:distributed_jobs:#{job.token}:state")).to eq(true)
        expect(redis.exists?("some_namespace:distributed_jobs:#{job.token}:parts")).to eq(true)

        expect(redis.exists?("distributed_jobs:#{job.token}:state")).to eq(false)
        expect(redis.exists?("distributed_jobs:#{job.token}:parts")).to eq(false)
      end
    end
  end
end
