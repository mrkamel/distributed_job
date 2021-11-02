# frozen_string_literal: true

module DistributedJob
  # A `DistributedJob::Client` allows to easily manage distributed jobs. The
  # main purpose of the client object is to configure settings to all
  # distributed jobs or a group of distributed jobs like e.g. the redis
  # connection and an optional namespace to be used to prefix all redis keys.
  #
  # @example
  #   DistributedJobClient = DistributedJob::Client.new(redis: Redis.new)
  #
  #   distributed_job = DistributedJobClient.build(token: SecureRandom.hex)
  #
  #   # Add job parts and queue background jobs
  #   distributed_job.push_each(Date.parse('2021-01-01')..Date.today) do |date, part|
  #     SomeBackgroundJob.perform_async(date, distributed_job.token, part)
  #   end
  #
  #   distributed_job.token # can be used to query the status of the distributed job

  class Client
    attr_reader :redis, :namespace, :default_ttl

    # Creates a new `DistributedJob::Client`.
    #
    # @param redis [Redis] The redis connection instance
    # @param namespace [String] An optional namespace used to prefix redis keys
    # @param default_ttl [Integer] The default number of seconds the jobs will
    #   stay available in redis. This value is used to automatically expire and
    #   clean up the jobs in redis. Default is 86400, i.e. one day. The ttl is
    #   used everytime the job is modified in redis.
    #
    # @example
    #   DistributedJobClient = DistributedJob::Client.new(redis: Redis.new)

    def initialize(redis:, namespace: nil, default_ttl: 86_400)
      @redis = redis
      @namespace = namespace
      @default_ttl = default_ttl
    end

    # Builds a new `DistributedJob::Job` instance.
    #
    # @param token [String] Some token to be used to identify the job. You can
    #   e.g. use SecureRandom.hex to generate one.
    # @param ttl [Integer] The number of seconds the job will stay available
    #   in redis. This value is used to automatically expire and clean up the
    #   job in redis. Default is `default_ttl`, i.e. one day. The ttl is used
    #   everytime the job is modified in redis.

    def build(token:, ttl: default_ttl)
      Job.new(client: self, token: token, ttl: ttl)
    end
  end
end
