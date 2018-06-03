//
//  DataLoaderError.swift
//  CNIOAtomics
//
//  Created by Kim de Vos on 02/06/2018.
//

import Foundation

public enum DataLoaderError: Error {
    case typeError(String)
    case noValueForKey(String)
}
