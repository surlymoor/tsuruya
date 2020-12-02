///
module tsuruya;

import std.range : ElementEncodingType, ElementType, isInputRange;
import std.traits : arity, isCallable, isType, Parameters, ReturnType, Unqual;

@safe:

/**
	Command-line parameter

	Params:
		identifier = The parameter's identifier used in the command-line interface and programming interface.
		T = The type of the value the parameter will take.
*/
struct Parameter(string identifier, T)
{
	mixin ParameterImpl!(identifier, T);
}

/// Command-line parameter's implementation
private mixin template ParameterImpl(string identifier, T)
{
	/// The parameter's name as used in the command-line interface and in the programming interface.
	static immutable id = identifier;
	/// The parameter's value, i.e. the value on which the parameter takes.
	T value;
}

/**
	Command-line parameter

	Params:
		identifier = The parameter's identifier used in the command-line interface and programming interface.
		processor = A callable object that processes the value given to the parameter. The type of the parameter's
			value is determined by the processor's return type.
*/
struct Parameter(string identifier, alias processor)
if (isValidParameterProcessor!processor)
{
	mixin ParameterImpl!(identifier, ReturnType!processor);
	/// Processes the value of the corresponding argument
	alias proc = processor;
}

/**
	Determines if a callable object may be used as a processor of command-line parameters and options.

	As mentioned, the object must be callable; it must take only one argument of type string; and it must return a
	value.

	Params:
		processor = The candidate.
*/
enum isValidParameterProcessor(alias processor) = isCallable!processor && arity!processor == 1
	&& is(Parameters!processor[0] == string) && !is(ReturnType!processor == void);

///
unittest
{
	// OK: It's a lambda, takes only one string, and returns a value.
	static assert(isValidParameterProcessor!((string value) => 42));
	// Invalid: It's a lambda, and it resolves to a value, but it takes multiple arguments.
	static assert(!isValidParameterProcessor!((string value, string otherValue) => 42));
	// Invalid: It's a template.
	static assert(!isValidParameterProcessor!((value) => 42));
	// Invalid: It's a lambda, and it returns a value, but it takes a non-string argument.
	static assert(!isValidParameterProcessor!((int value) => 42));
	// Invalid: It's a lambda, takes only one string, but it doesn't resolve to anything.
	static assert(!isValidParameterProcessor!((string value) { return; }));
}

/**
	Command-line option

	Params:
		nameSpecification = The specification by which an option's long name, short name, aliases, and behavior are
			determined. Please see the documentation of `std.getopt` for more information on its syntax and semantics.
		T = The type of the value the option will take.
		defaultValue = The value the option will take if it's not specified in the command-line arguments.
		optionSettings = "Optional" metadata.
*/
struct Option(string nameSpecification, T, T defaultValue, optionSettings...)
{
	mixin OptionImpl!(nameSpecification, T, defaultValue, optionSettings);
}

/**
	Command-line option

	Params:
		nameSpecification = The specification by which an option's long name, short name, aliases, and behavior are
			determined. Please see the documentation of `std.getopt` for more information on its syntax and semantics.
		T = The type of the value the option will take.
		optionSettings = "Optional" metadata.
*/
struct Option(string nameSpecification, T, optionSettings...)
{
	mixin OptionImpl!(nameSpecification, T, T.init, optionSettings);
}

/**
	Command-line option

	Params:
		nameSpecification = The specification by which an option's long name, short name, aliases, and behavior are
			determined. Please see the documentation of `std.getopt` for more information on its syntax and semantics.
		defaultValue = The value the option will take if it's not specified in the command-line arguments. The type of
			the option's value will be deduced from this default value.
		optionSettings = "Optional" metadata.
*/
struct Option(string nameSpecification, alias defaultValue, optionSettings...)
if (!isType!defaultValue && !isValidParameterProcessor!defaultValue)
{
	mixin OptionImpl!(nameSpecification, typeof(defaultValue), defaultValue, optionSettings);
}

/**
	Command-line option

	Params:
		nameSpecification = The specification by which an option's long name, short name, aliases, and behavior are
			determined. Please see the documentation of `std.getopt` for more information on its syntax and semantics.
		processor = A callable object that processes value given to the option. The type of the option's value is
			determined by the processor's return type.
		defaultValue = The value the option will take if it's not specified in the command-line arguments.
		optionSettings = "Optional" metadata.
*/
struct Option(string nameSpecification, alias processor, alias defaultValue, optionSettings...)
if (isValidParameterProcessor!processor & !isType!defaultValue)
{
	mixin OptionImpl!(nameSpecification, ReturnType!processor, defaultValue, optionSettings);
	/// Processes the option's given value.
	alias proc = processor;
}

/**
	Command-line option

	Params:
		nameSpecification = The specification by which an option's long name, short name, aliases, and behavior are
			determined. Please see the documentation of `std.getopt` for more information on its syntax and semantics.
		processor = A callable object that processes value given to the option. The type of the option's value is
			determined by the processor's return type.
		optionSettings = "Optional" metadata.
*/
struct Option(string nameSpecification, alias processor, optionSettings...)
if (isValidParameterProcessor!processor)
{
	mixin OptionImpl!(nameSpecification, ReturnType!processor, ReturnType!processor.init, optionSettings);
	/// Processes the option's given value.
	alias proc = processor;
}

/// Command-line option's implementation
private mixin template OptionImpl(string nameSpecification, T, alias defaultValue, settings...)
{
	mixin OptionSettings!settings;
	mixin OptionNames!nameSpecification;
	///
	static immutable nameSpec = nameSpecification;
	///
	T value = defaultValue;
}

/// Definitions of an option's various names derived from `nameSpecification`.
private mixin template OptionNames(string nameSpecification)
{
	import std.algorithm : splitter, until;
	import std.conv : to;
	static immutable longName = nameSpecification.until("|").until("+").to!string;
	static immutable shortName = nameSpecification.splitter('|').shortName;
}

unittest
{
	{
		mixin OptionNames!"option";
		static assert(longName == "option");
		static assert(shortName.length == 0);
	}
	{
		mixin OptionNames!"option|o";
		static assert(longName == "option");
		static assert(shortName == "o");
	}
	{
		mixin OptionNames!"option+";
		static assert(longName == "option");
		static assert(shortName.length == 0);
	}
	{
		mixin OptionNames!"option|o+";
		static assert(longName == "option");
		static assert(shortName == "o");
	}
	{
		mixin OptionNames!"option|o|setting+";
		static assert(longName == "option");
		static assert(shortName == "o");
	}
}

/**
	Returns the first element of a range that consists of one character and thus is considered a "short name".

	Params:
		range = An input range whose elements are convertible to `char` arrays. It is assumed that every element does
			not contain a bar '|'.
*/
pure
private auto shortName(R)(R range)
if (isInputRange!R && is(Unqual!(ElementEncodingType!(ElementType!R)) : char))
{
	import std.algorithm : filter, map, until;
	import std.conv : to;
	import std.range : front, walkLength;
	auto result = range.map!(r => r.until("+")).filter!(r => r.walkLength == 1);
	if (result.empty) return "";
	else return result.front.to!string;
}

/// Instances of `OptionSetting` types contained in `settings`.
private mixin template OptionSettings(settings...)
{
	static foreach (setting; settings)
	{
		mixin(q{static immutable }, typeof(setting).id, q{ = setting.value;});
	}
}

/// A category under which the option is placed in the help text.
alias OptionCategory = OptionSetting!("category", string);
/// A description of the option as seen in the help text
alias OptionDesc = OptionSetting!("desc", string);
/// A more elaborated description of the option
alias OptionHelp = OptionSetting!("help", string);
/// A signal as to whether the option is required to be present in the command-line arguments.
alias OptionRequired = OptionSetting!("required", bool, true);

///
private struct OptionSetting(string identifier, T, T defaultValue = T.init)
{
	private static immutable id = identifier;
	///
	T value = defaultValue;
}

///
auto parseArgs(CLIObjs)(string[] args)
{

}