# CHANGELOG

## v3.1.0

* Added `DistributedJob::Job#push_all`
* Added `DistributedJob::Job#open_part?`

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
