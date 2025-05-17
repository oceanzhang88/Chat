//
//  KeyPath+Hack.swift
//  Chat
//


#if swift(>=6.0)
extension KeyPath: @unchecked @retroactive Sendable { }
#else
extension KeyPath: @unchecked Sendable { }
#endif
