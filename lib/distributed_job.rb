# frozen_string_literal: true

require 'distributed_job/version'
require 'redis'

# A distributed job instance allows to keep track of distributed jobs, i.e.
# jobs which are split into multiple units running in parallel and in multiple
# workers using redis.
#
# @example Creating a distributed job
#   distributed_job = DistributedJob.new(redis: Redis.new, token: SecureRandom.hex)
#
#   distributed_job.push_each(Date.parse('2021-01-01')..Date.today) do |date, part|
#     SomeBackgroundJob.perform_async(date, distributed_job.token, part)
#   end
#
#   distributed_job.token # can be used to query the status of the distributed job
#
# @example Processing a distributed job part
#   class SomeBackgroundJob
#     def perform(whatever, token, part)
#       distributed_job = DistributedJob.new(redis: Redis.new, token: token)
#
#       return if distributed_job.stopped?
#
#       # ...
#
#       distributed_job.done(part)
#
#       if distributed_job.finished?
#         # perform e.g. cleanup or the some other job
#       end
#     rescue
#       distributed_job.stop
#
#       raise
#     end
#   end

class DistributedJob
  attr_reader :redis, :token, :ttl

  # Initializes a new distributed job.
  #
  # @param redis [Redis] The redis connection instance
  # @param token [String] Some token to be used to identify the job. You can
  #   e.g. use SecureRandom.hex to generate one.
  # @param ttl [Integer] The number of seconds this job will stay available
  #   in redis. This value is used to automatically expire and clean up the
  #   job in redis. Default is 86400, i.e. one day. The ttl is used everytime
  #   the job is modified in redis.
  #
  # @example
  #   distributed_job = DistributedJob.new(redis: Redis.new, token: SecureRandom.hex)

  def initialize(redis:, token:, ttl: 86_400)
    @redis = redis
    @token = token
    @ttl = ttl
  end

  # Pass an enum to be used to iterate all the units of work of the distributed
  # job. The distributed job needs to know all of them to keep track of the
  # overall number and status of the parts. Passing an enum is much better
  # compared to pushing the parts manually, because the distributed job needs
  # to be closed before the last part of the distributed job is enqueued into
  # some job queue. Otherwise it could potentially happen that the last part is
  # already processed in the job queue before it is pushed to redis, such that
  # the last job doesn't know that the distributed job is finished.
  #
  # @param enum [#each_with_index] The enum which can be iterated to get all
  #   job parts
  #
  # @example
  #   distributed_job.push_each(Date.parse('2021-01-01')..Date.today) do |date, part|
  #     # e.g. SomeBackgroundJob.perform_async(date, distributed_job.token, part)
  #   end
  #
  # @example ActiveRecord
  #   distributed_job.push_each(User.select(:id).find_in_batches) do |batch, part|
  #     # e.g. SomeBackgroundJob.perform_async(batch.first.id, batch.last.id, distributed_job.token, part)
  #   end

  def push_each(enum)
    return enum_for(:push_each, enum) unless block_given?

    previous_object = nil
    previous_index = nil

    enum.each_with_index do |current_object, current_index|
      push(current_index)

      yield(previous_object, previous_index.to_s) if previous_index

      previous_object = current_object
      previous_index = current_index
    end

    close

    yield(previous_object, previous_index.to_s) if previous_index
  end

  # Returns all pushed parts of the distributed job
  #
  # @return [Enumerator] The enum which allows to iterate all parts

  def parts
    redis.sscan_each("#{redis_key}:parts")
  end

  # Removes the specified part from the distributed job, i.e. from the set of
  # unfinished parts. Use this method when the respective job part has been
  # successfully processed, i.e. finished.
  #
  # @param part [String] The job part
  # @returns [Boolean] Returns true when there are no more unfinished parts
  #   left or false otherwise
  #
  # @example
  #   class SomeBackgroundJob
  #     def perform(whatever, token, part)
  #       distributed_job = DistributedJob.new(redis: Redis.new, token: token)
  #
  #       # ...
  #
  #       distributed_job.done(part)
  #     end
  #   end

  def done(part)
    @done_script ||= <<~SCRIPT
      local key, part, ttl = ARGV[1], ARGV[2], tonumber(ARGV[3])

      if redis.call('srem', key .. ':parts', part) == 0 then return end

      redis.call('expire', key .. ':parts', ttl)
      redis.call('expire', key .. ':state', ttl)

      return redis.call('scard', key .. ':parts')
    SCRIPT

    redis.eval(@done_script, argv: [redis_script_key, part.to_s, ttl]) == 0 && closed?
  end

  # Returns the total number of pushed parts, no matter if finished or not.
  #
  # @example
  #   distributed_job.total # => e.g. 13

  def total
    redis.hget("#{redis_key}:state", 'total').to_i
  end

  # Returns the number of pushed parts which are not finished.
  #
  # @example
  #   distributed_job.count # => e.g. 8

  def count
    redis.scard("#{redis_key}:parts")
  end

  # Returns true if there are no more unfinished parts.
  #
  # @example
  #   distributed_job.finished? #=> true/false

  def finished?
    closed? && count.zero?
  end

  # Allows to stop a distributed job. This is useful if some error occurred in
  # some part, i.e. background job, of the distributed job and you then want to
  # stop all other not yet finished parts. Please note that only jobs can be
  # stopped which ask the distributed job actively whether or not it was
  # stopped.
  #
  # @returns [Boolean] Always returns true
  #
  # @example
  #   class SomeBackgroundJob
  #     def perform(whatever, token, part)
  #       distributed_job = DistributedJob.new(redis: Redis.new, token: token)
  #
  #       return if distributed_job.stopped?
  #
  #       # ...
  #
  #       distributed_job.done(part)
  #     rescue
  #       distributed_job.stop
  #
  #       raise
  #     end
  #   end

  def stop
    redis.multi do
      redis.hset("#{redis_key}:state", 'stopped', 1)

      redis.expire("#{redis_key}:state", ttl)
      redis.expire("#{redis_key}:parts", ttl)
    end

    true
  end

  # Returns true when the distributed job was stopped or false otherwise.
  #
  # @returns [Boolean] Returns true or false
  #
  # @example
  #   class SomeBackgroundJob
  #     def perform(whatever, token, part)
  #       distributed_job = DistributedJob.new(redis: Redis.new, token: token)
  #
  #       return if distributed_job.stopped?
  #
  #       # ...
  #
  #       distributed_job.done(part)
  #     rescue
  #       distributed_job.stop
  #
  #       raise
  #     end
  #   end

  def stopped?
    redis.hget("#{redis_key}:state", 'stopped') == '1'
  end

  private

  def close
    redis.multi do
      redis.hset("#{redis_key}:state", 'closed', 1)

      redis.expire("#{redis_key}:state", ttl)
      redis.expire("#{redis_key}:parts", ttl)
    end

    true
  end

  def closed?
    redis.hget("#{redis_key}:state", 'closed') == '1'
  end

  def push(part)
    @push_script ||= <<~SCRIPT
      local key, part, ttl = ARGV[1], ARGV[2], tonumber(ARGV[3])

      if redis.call('sadd', key .. ':parts', part) == 1 then
        redis.call('hincrby', key .. ':state', 'total', 1)
      end

      redis.call('expire', key .. ':parts', ttl)
      redis.call('expire', key .. ':state', ttl)
    SCRIPT

    redis.eval(@push_script, argv: [redis_script_key, part.to_s, ttl])
  end

  def redis_key
    @redis_key ||= "distributed_jobs:#{token}"
  end

  def redis_script_key
    return "#{redis.namespace}:#{redis_key}" if redis.respond_to?(:namespace)

    redis_key
  end
end
