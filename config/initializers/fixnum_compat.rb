# Ruby 2 -> 3 compatibility for old gems (e.g., annotate 2.x)
Fixnum = Integer unless defined?(Fixnum)
Bignum = Integer unless defined?(Bignum)