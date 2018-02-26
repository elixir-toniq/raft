Cluster configuration is discussed in section 6 of the raft paper. The
paper is the authoritative source but this is a brief overview of the
cluster changes.

## Example 

Lets say the initial cluster is `:a`, `:b`, and `:c`. Two new
peers, `:d`, and `:e` need to be added to the cluster. The configuration
change request is sent to the leader of the cluster which we will suppose
is node `:a`. Because `:d` and `:e` may not store any logs yet we need to
catch them up before we start the configuration change. The reason for
this will become clear in a moment but for now just understand that if we
don't catch these nodes up first we can cause periods of unavailability
while the configuration change is taking place. During this initial period
`:d` and `:e` have no "suffrage"; They have no voting power and are not
considered for any majorities. Once the new nodes have been caught up with
the leader the leader can initiate the cluster change.

In order to remain consistent the cluster change must take place in two
phases. 

## Step 1 - Joint Consensus

To start the first phase a leader appends a new configuration entry to its
log which includes the old peers and the new peers. The log entry might
look like this: `%{old_peers: [:a, :b, :c], new_peers: [:d, :e]}`.


## Notes

* In the even that the leader crashes the new nodes need to coordinate and
  discover a new leader and request a configuration change again.
