# CHANGELOG

## v3.1.0

* Added `DistributedJob::Job#push_in_batches` to make it easier when you want
  one background job to process multiple parts of a distributed job
* Added `DistributedJob::Job#open_part?` to determine whether or not a part
  is still open

## v3.0.1

* Fix pipelining with regards to redis-rb 4.6.0

## v3.0.0

* Split `DistributedJob` in `DistributedJob::Client` and `DistributedJob::Job`
* Add native namespace support and drop support for `Redis::Namespace`

## v2.0.0

* `#push_each` no longer returns an enum when no block is given
* Renamed `#parts` to `#open_parts`

## v1.0.0

* Initial release
