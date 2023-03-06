"use strict";

export const isNonemptyString = (v) => typeof(v) == "string" && v.trim().length > 0;

export const existsInArray = (haystack, needle) => haystack.find(v => (v == needle)) !== undefined;
