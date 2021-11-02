# frozen_string_literal: true

require File.expand_path('../spec_helper', __dir__)

module DistributedJob
  RSpec.describe Client do
    let(:redis) { Redis.new }

    describe '#build' do
      it 'returns a new job' do
        expect(described_class.new(redis: redis).build(token: SecureRandom.hex)).to be_instance_of(DistributedJob::Job)
      end

      context 'with params' do
        let(:client) { described_class.new(redis: redis) }

        before do
          allow(DistributedJob::Job).to receive(:new)
        end

        it 'passes the correct default ttl' do
          client.build(token: 'token')

          expect(DistributedJob::Job).to have_received(:new).with(client: client, token: 'token', ttl: 86_400)
        end

        it 'allows to overwrite the ttl' do
          client.build(token: 'token', ttl: 60)

          expect(DistributedJob::Job).to have_received(:new).with(client: client, token: 'token', ttl: 60)
        end
      end
    end
  end
end
