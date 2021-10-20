# DistributedJob

Easily keep track of distributed jobs consisting of an arbitrary number of
parts spanning multiple workers using redis. Can be used with any kind of
backround job processing queue.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'distributed_job'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install distributed_job

## Usage

Getting started is very easy. A `DistributedJob` allows to keep track of a
distributed job, i.e. a job which is split into multiple units running in
parallel and in multiple workers.

To create a distributed job and add parts, i.e. units of work, to it, simply:

```ruby
  distributed_job = DistributedJob.new(redis: Redis.new, token: SecureRandom.hex)

  distributed_job.push_each(Date.parse('2021-01-01')..Date.today) do |date, part|
    SomeBackgroundJob.perform_async(date, distributed_job.token, part)
  end

  distributed_job.token # can be used to query the status of the distributed job
```

The `part` which is passed to the block is some id for one particular part of
the distributed job. It must be used in a respective background job to mark
this part finished after it has been successfully processed. Therefore, when
all those background jobs have successfully finished, all parts will be marked
as finished, such that the distributed job will finally be finished as well.

The `token` can be used to keep query the status of the distributed job, e.g.
on a job summary page or similar. You can show some progress bar in the browser
or in the terminal, etc:

```ruby
# token is given via URL or via some other means
distributed_job = Distributed.new(redis: Redis.new, token: params[:token])

distributed_job.total # total number of parts
distributed_job.count # number of unfinished parts
distributed_job.finished? # whether or not all parts are finished
distributed_job.open_parts # returns all not yet finished part id's
```

Within the background job, you use the passed token and part to query and
update the status of the distributed job and part accordingly. Please note
that you can use whatever background job processing tool you like most.

```ruby
class SomeBackgroundJob
  def perform(whatever, token, part)
    distributed_job = DistributedJob.new(redis: Redis.new, token: token)

    return if distributed_job.stopped?

    # ...

    distributed_job.done(part)

    if distributed_job.finished?
      # perform e.g. cleanup or the some other job
    end
  rescue
    distributed_job.stop

    raise
  end
end
```

The `#stop` and `#stopped?` methods can be used to globally stop a distributed
job in case of errors. Contrary, the `#done` method tells the `DistributedJob` that the
specified part has successfully finished. Finally, the `#finished?` method
returns true when all parts of the distributed job are finished, which is useful
to start cleanup jobs or to even start another subsequent distributed job.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run
`bundle exec rspec` to run the tests. You can also run `bin/console` for an
interactive prompt that will allow you to experiment.

## Contributing

Bug reports and pull requests are welcome on GitHub at
https://github.com/mrkamel/distributed_job.

## License

The gem is available as open source under the terms of the [MIT
License](https://opensource.org/licenses/MIT).
