# Tson

TSON is a an "object/data" [de]serialization protocol that was inspired by an application specific need to have an interchange encoder/decoder that was JSON like. It was further inspired by BSON which is binary and has a richer typeset. But BSON has lots of extra byte offsets convenient for random access computations.

The basic structue is an [opcode | moredata] recursive chaining of data.

It was tuned to fit our own application's nuances and further inspired by far too much familiarity with Smalltalk Virtual Machine bytecode design as well a general appreciation for Benford's Law (smaller values show up more often than not in many real world cases).

The "T" stands for Tiny, Tight, Terse, or TWiG, but not Travis.
