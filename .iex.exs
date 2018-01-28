pack = fn int -> << int :: size(64) >> end

move = fn (itr, pos) ->
  {:ok, k, v} = :rocksdb.iterator_move(itr, pos)
  {:binary.decode_unsigned(k), :erlang.binary_to_term(v)}
end

test_db = fn() ->
  {:ok, db} = :rocksdb.open('test.db', create_if_missing: true)
  db
end

itr = fn db ->
  {:ok, iterator} = :rocksdb.iterator(db, [])
  iterator
end
