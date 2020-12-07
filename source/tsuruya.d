/**
	tsuruya is a a command-line argument processing library, all contained in one module.

	License: 0BSD (See LICENSE.)
*/
module tsuruya;

import std.range : ElementEncodingType, ElementType, isInputRange;
import std.traits : arity, isAggregateType, isCallable, isInstanceOf, isType, Parameters, ReturnType, Unqual;

@safe:

/**
	Command-line operand

	The type of the operand's value determines how an argument (or arguments) will be processed into the operand.
	Specifically, if the type is a dynamic array, or slice, then any remaining, non-option arguments will be converted
	to the type of the type's elements and be placed into the operand. If the type is a static array, or slice, then at
	most k-number of non-option arguments will be converted to the type of the type's elements and be placed into the
	operand's value, where k is the type's static length. If the type isn't any kind of array, or slice, then only one
	argument will be taken, converted, and become the operand's value. (Output ranges are not yet supported.)

	Params:
		identifier = The operand's identifier as used in the command-line interface and programming interface. For
			the latter, simple transformations will be performed to make it into a valid D identifier. If the latter
			conflicts with a D keyword, e.g. `version`, then an underscore will be prefixed to it, e.g. "_version".
		T = The type of value the operand will take.
		settings = Optional metadata
*/
struct Operand(string identifier, T = string, settings...)
{
	mixin OperandImpl!(identifier, T, settings);
}

/**
	Command-line operand

	The one parameter of the operand's `processor` may be of three different types: `string`, `string[]`, and
	`string[k]`, where 'k' is some natural number and denotes the latter of the three as being a static array, or
	slice. Thus, instead of the type of the operand's value determining the method by which an argument (or arguments)
	will be manipulated and placed into the operand, it will be the type of this one parameter of `processor`.
	Otherwise, the same rules apply.

	Params:
		identifier = The operand's identifier as used in the command-line interface and programming interface. For
			the latter, simple transformations will be performed to make it into a valid D identifier. If the latter
			conflicts with a D keyword, e.g. `version`, then an underscore will be prefixed to it, e.g. "_version".
		processor = A callable object that processes the value given to the operand. The type of the operand's
			value is determined by the processor's return type.
		settings = Optional metadata
*/
struct Operand(string identifier, alias processor, settings...)
if (isOperandProcessor!processor)
{
	mixin OperandImpl!(identifier, ReturnType!processor, settings);
	/// Processes the value of the corresponding argument
	alias proc = processor;
}

/// Command-line operand's implementation
private mixin template OperandImpl(string identifier, T, settings...)
{
	mixin ParameterSettings!settings;
	/// The operand's name as used in the command-line interface
	static immutable name = identifier;
	/// The operand's name as used as in code generation.
	static immutable id = identifier.extractID;
	/// The operand's value, i.e. the value on which the operand takes.
	T value;
}

/**
	Determines if a callable object may be used as a processor of command-line operands.

	As mentioned, the object must be callable; it must take only one argument of type `string` or an array/static array
	of strings, and it must return a value.

	Params:
		processor = The candidate.
*/
enum isOperandProcessor(alias processor) = isCallable!processor && arity!processor == 1
	&& (is(Parameters!processor[0] == string) || is(ElementType!(Parameters!processor[0]) == string))
	&& !is(ReturnType!processor == void);

///
unittest
{
	// OK: It's a lambda, takes only one string, and returns a value.
	static assert(isOperandProcessor!((string value) => 42));
	// OK: It's a lambda, takes an array of strings, and returns a value.
	static assert(isOperandProcessor!((string[] values) => 42));
	// OK: It's a lambda, takes a static array of strings, and returns a value.
	static assert(isOperandProcessor!((string[2] values) => 42));
	// Invalid: It's a lambda, and it resolves to a value, but it takes multiple arguments.
	static assert(!isOperandProcessor!((string value, string otherValue) => 42));
	// Invalid: It's a template.
	static assert(!isOperandProcessor!((value) => 42));
	// Invalid: It's a lambda, and it returns a value, but it takes a non-string, non-array-of-strings argument.
	static assert(!isOperandProcessor!((int value) => 42));
	// Invalid: It's a lambda, takes only one string, but it doesn't resolve to anything.
	static assert(!isOperandProcessor!((string value) { return; }));
}

/**
	Extracts a valid D identifier from a command-line parameter's name.

	If the input is separated by hyphens, those hyphens will be removed; the first character of each block of text
	after each hyphen will be capitalized, if possible. Thus, the result will be in camel case. If, after processing,
	`range` still contains an invalid character for a D identifier, an error will be thrown. If the `range` conflicts
	with a D keyword, e.g. `version`, then an underscore will be prefixed to it, e.g. "_version".

	Params:
		range = An input range whose elements are convertible to `char`.

	Returns: A variation of the input that's a valid D identifier.
*/
pure
private string extractID(R)(R range)
if (isInputRange!R && is(Unqual!(ElementEncodingType!R) : char))
{
	import std.algorithm : canFind, equal, joiner, map, splitter;
	import std.conv: to;
	import std.range : chain, dropOne, front, walkLength;
	import std.uni : asCapitalized, isAlpha, isAlphaNum;
	auto words = range.splitter("-");
	if (words.walkLength == 1)
	{
		if (range.isKeyword) return "_" ~ range;
		else return range;
	}
	auto id = words.front.chain(words.dropOne.map!asCapitalized.joiner).to!string;
	if (id.front != '_' && !id.front.isAlpha) assert(0,
		"A D identifier must only begin with an underscore or (universal) alphabetic character");
	if (id[1..$].canFind!(ch => ch != '_' && !ch.isAlphaNum)) assert(0,
		"A D identifier may only contain underscores, numbers, and (universal) alphabetic characters");
	if (id.isKeyword) return "_" ~ id;
	else return id;
}

@trusted
unittest
{
	import core.exception : AssertError;
	import std.exception : assertThrown;
	static assert("long-option-name".extractID == "longOptionName");
	static assert("version".extractID == "_version");
	assertThrown!AssertError("inv@lid-option-nam$".extractID);
	assertThrown!AssertError("42-option-name".extractID);
}

/**
	Determines whether a range of characters is equal to a D keyword.

	Params:
		range = An input range whose elements are convertible to `char`.
*/
pure
private bool isKeyword(R)(R range)
if (isInputRange!R && is(Unqual!(ElementEncodingType!R) : char))
{
	import std.algorithm : equal;

	if (range.equal("abstract")) return true;
	else if (range.equal("alias")) return true;
	else if (range.equal("align")) return true;
	else if (range.equal("asm")) return true;
	else if (range.equal("assert")) return true;
	else if (range.equal("auto")) return true;
	else if (range.equal("body")) return true;
	else if (range.equal("bool")) return true;
	else if (range.equal("break")) return true;
	else if (range.equal("byte")) return true;
	else if (range.equal("case")) return true;
	else if (range.equal("cast")) return true;
	else if (range.equal("catch")) return true;
	else if (range.equal("cdouble")) return true;
	else if (range.equal("cent")) return true;
	else if (range.equal("cfloat")) return true;
	else if (range.equal("char")) return true;
	else if (range.equal("class")) return true;
	else if (range.equal("const")) return true;
	else if (range.equal("continue")) return true;
	else if (range.equal("creal")) return true;
	else if (range.equal("dchar")) return true;
	else if (range.equal("debug")) return true;
	else if (range.equal("default")) return true;
	else if (range.equal("delegate")) return true;
	else if (range.equal("delete")) return true;
	else if (range.equal("deprecated")) return true;
	else if (range.equal("do")) return true;
	else if (range.equal("double")) return true;
	else if (range.equal("else")) return true;
	else if (range.equal("enum")) return true;
	else if (range.equal("export")) return true;
	else if (range.equal("extern")) return true;
	else if (range.equal("false")) return true;
	else if (range.equal("final")) return true;
	else if (range.equal("finally")) return true;
	else if (range.equal("float")) return true;
	else if (range.equal("for")) return true;
	else if (range.equal("foreach")) return true;
	else if (range.equal("foreach_reverse")) return true;
	else if (range.equal("function")) return true;
	else if (range.equal("goto")) return true;
	else if (range.equal("idouble")) return true;
	else if (range.equal("if")) return true;
	else if (range.equal("ifloat")) return true;
	else if (range.equal("immutable")) return true;
	else if (range.equal("import")) return true;
	else if (range.equal("in")) return true;
	else if (range.equal("inout")) return true;
	else if (range.equal("int")) return true;
	else if (range.equal("interface")) return true;
	else if (range.equal("invariant")) return true;
	else if (range.equal("ireal")) return true;
	else if (range.equal("is")) return true;
	else if (range.equal("lazy")) return true;
	else if (range.equal("long")) return true;
	else if (range.equal("macro")) return true;
	else if (range.equal("mixin")) return true;
	else if (range.equal("module")) return true;
	else if (range.equal("new")) return true;
	else if (range.equal("nothrow")) return true;
	else if (range.equal("null")) return true;
	else if (range.equal("out")) return true;
	else if (range.equal("override")) return true;
	else if (range.equal("package")) return true;
	else if (range.equal("pragma")) return true;
	else if (range.equal("private")) return true;
	else if (range.equal("protected")) return true;
	else if (range.equal("public")) return true;
	else if (range.equal("pure")) return true;
	else if (range.equal("real")) return true;
	else if (range.equal("ref")) return true;
	else if (range.equal("return")) return true;
	else if (range.equal("scope")) return true;
	else if (range.equal("shared")) return true;
	else if (range.equal("short")) return true;
	else if (range.equal("static")) return true;
	else if (range.equal("struct")) return true;
	else if (range.equal("super")) return true;
	else if (range.equal("switch")) return true;
	else if (range.equal("synchronized")) return true;
	else if (range.equal("template")) return true;
	else if (range.equal("this")) return true;
	else if (range.equal("throw")) return true;
	else if (range.equal("true")) return true;
	else if (range.equal("try")) return true;
	else if (range.equal("typeid")) return true;
	else if (range.equal("typeof")) return true;
	else if (range.equal("ubyte")) return true;
	else if (range.equal("ucent")) return true;
	else if (range.equal("uint")) return true;
	else if (range.equal("ulong")) return true;
	else if (range.equal("union")) return true;
	else if (range.equal("unittest")) return true;
	else if (range.equal("ushort")) return true;
	else if (range.equal("version")) return true;
	else if (range.equal("void")) return true;
	else if (range.equal("wchar")) return true;
	else if (range.equal("while")) return true;
	else if (range.equal("with")) return true;
	else if (range.equal("__FILE__")) return true;
	else if (range.equal("__FILE_FULL_PATH__")) return true;
	else if (range.equal("__MODULE__")) return true;
	else if (range.equal("__LINE__")) return true;
	else if (range.equal("__FUNCTION__")) return true;
	else if (range.equal("__PRETTY_FUNCTION__")) return true;
	else if (range.equal("__gshared")) return true;
	else if (range.equal("__traits")) return true;
	else if (range.equal("__vector")) return true;
	else if (range.equal("__parameters")) return true;

	return false;
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
struct Option(string nameSpecification, T = string, optionSettings...)
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
if (!isType!defaultValue && !isOperandProcessor!defaultValue)
{
	mixin OptionImpl!(nameSpecification, typeof(defaultValue), defaultValue, optionSettings);
}

/**
	Command-line option

	Params:
		nameSpecification = The specification by which an option's long name, short name, aliases, and behavior are
			determined. Please see the documentation of `std.getopt` for more information on its syntax and semantics.
		processor = A callable object that processes the value given to the option. The type of the option's value is
			determined by the processor's return type.
		defaultValue = The value the option will take if it's not specified in the command-line arguments.
		optionSettings = "Optional" metadata.
*/
struct Option(string nameSpecification, alias processor, alias defaultValue, optionSettings...)
if (isOperandProcessor!processor & !isType!defaultValue)
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
		processor = A callable object that processes the value given to the option. The type of the option's value is
			determined by the processor's return type.
		optionSettings = "Optional" metadata.
*/
struct Option(string nameSpecification, alias processor, optionSettings...)
if (isOperandProcessor!processor)
{
	mixin OptionImpl!(nameSpecification, ReturnType!processor, ReturnType!processor.init, optionSettings);
	/// Processes the option's given value.
	alias proc = processor;
}

/// Command-line option's implementation
private mixin template OptionImpl(string nameSpecification, T, alias defaultValue, settings...)
{
	mixin OptionNames!nameSpecification;
	mixin ParameterSettings!settings;
	/// The option's name specification for use with std.getopt
	static immutable nameSpec = nameSpecification;
	/// The option's default value
	static immutable defVal = defaultValue;
	/// The option's value
	T value = defaultValue;
}

/**
	Determines if a callable object may be used as a processor of command-line operands.

	As mentioned, the object must be callable; it must take only one argument of type `string`; and it must
	return a value.

	Params:
		processor = The candidate.
*/
enum isOptionProcessor(alias processor) = isCallable!processor && arity!processor == 1
	&& is(Parameters!processor[0] == string) && !is(ReturnType!processor == void);

///
unittest
{
	// OK: It's a lambda, takes only one string, and returns a value.
	static assert(isOptionProcessor!((string value) => 42));
	// Invalid: It's a lambda, and it resolves to a value, but it takes multiple arguments.
	static assert(!isOptionProcessor!((string value, string otherValue) => 42));
	// Invalid: It's a template.
	static assert(!isOptionProcessor!((value) => 42));
	// Invalid: It's a lambda, and it returns a value, but it takes a non-string, non-array-of-strings argument.
	static assert(!isOptionProcessor!((int value) => 42));
	// Invalid: It's a lambda, takes only one string, but it doesn't resolve to anything.
	static assert(!isOptionProcessor!((string value) { return; }));
}

/// Definitions of an option's various names derived from `nameSpecification`.
private mixin template OptionNames(string nameSpecification)
{
	import std.algorithm : splitter, until;
	import std.conv : to;
	/// The long name of an option
	static immutable longName = nameSpecification.until("|").until("+").to!string;
	/// The short, one-letter name of an option. If the spec didn't have one, this will be empty.
	static immutable shortName = nameSpecification.splitter('|').extractShortName;
	/**
		The name used in code generation and the subsequent programming interface to identify an option. If it would
		have conflicted with a D keyword, e.g. `version`, then an underscore would have been prefixed to it, e.g.
		"_version".
	*/
	static immutable id = longName.extractID;
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
private auto extractShortName(R)(R range)
if (isInputRange!R && is(Unqual!(ElementEncodingType!(ElementType!R)) : char))
{
	import std.algorithm : filter, map, until;
	import std.conv : to;
	import std.range : front, walkLength;
	auto result = range.map!(r => r.until("+")).filter!(r => r.walkLength == 1);
	if (result.empty) return "";
	else return result.front.to!string;
}

/**
	Returns the aliases of a command-line option as specified by its name specification.

	Params:
		spec = The name specification of an command-line option.

	Returns: An array of strings whose elements are the aliases. If no aliases were named in `spec`, then an empty
		array is returned.
*/
pure private string[] extractAliases(string spec)
{
	import std.algorithm : filter, map, splitter, until;
	import std.array : array;
	import std.conv : to;
	import std.range : dropOne, walkLength;
	auto result = spec.splitter("|").dropOne.map!(name => name.until("+")).filter!(name => name.walkLength > 1);
	if (result.empty) return [];
	else return result.map!(to!string).array;
}

unittest
{
	assert("verbose|v|garrulous|loquacious".extractAliases == ["garrulous", "loquacious"]);
	assert("verbose|v".extractAliases.length == 0);
	assert("verbose".extractAliases.length == 0);
}

/// Field definitions of command-line parameter settings.
private mixin template ParameterSettings(settings...)
{
	import std.traits : getSymbolsByUDA;
	static foreach (setting; settings)
	{
		mixin(q{static immutable }, typeof(setting).id, q{ = setting.value;});
	}
}

/// A category under which the command-line parameter is placed in the help text.
struct ParamCategory
{
	mixin ParameterSettingImpl!("category", string, "");
}
/// A description of the command-line parameter as seen in the help text
struct ParamDesc
{
	mixin ParameterSettingImpl!("desc", string, "");
}
/// A more elaborated description of the command-line parameter
struct ParamHelp
{
	mixin ParameterSettingImpl!("help", string, "");
}
/// A signal as to whether the command-line parameter is required to be present in the command-line arguments.
struct ParamRequired
{
	mixin ParameterSettingImpl!("required", bool);
}

/// Command-line parameter setting implementation
private mixin template ParameterSettingImpl(string identifier, T, T defaultValue = T.init)
{
	private static immutable id = identifier;
	private static immutable defVal = defaultValue;
	/// The setting's value
	auto value = defaultValue;
}

///
auto parseArgs(CommandLineParameters...)(string[] args)
{
	import std.getopt : config, getopt;
	import std.meta : AliasSeq, ApplyLeft, Filter;
	import std.path : baseName;
	import std.traits : hasMember;

	alias Operands = Filter!(ApplyLeft!(isInstanceOf, Operand), CommandLineParameters);
	// When creating `Options`, we must ensure that the help option, which will be added if it wasn't specified, is the
	// first element; `getopt` will only handle it during the first invocation.
	enum isHelpOption(Option) = Option.longName == "help" && Option.shortName == "h";
	alias Options = BringToFront!(isHelpOption, Option!("help|h", bool, ParamDesc("Print this help")),
		Filter!(ApplyLeft!(isInstanceOf, Option), CommandLineParameters));
	alias CommandLineParameters = AliasSeq!(Operands, Options);
	Operands operands;
	Options options;

	static foreach (i, Opt; Options)
	{{
		alias opt = options[i];
		static if (hasMember!(Opt, "proc"))
		{
			args.getopt(config.passThrough, Opt.nameSpec,
				(string name, string value) { opt.value = Opt.proc(value); });
		}
		else args.getopt(config.passThrough, Opt.nameSpec, &opt.value);
	}}
	// Catch any unrecognized options
	args.getopt;

	// Handle the operands
	{
		import std.algorithm : filter;
		import std.range : dropExactly, dropOne, front, walkLength;
		auto operandArgs = args.dropOne.filter!(arg => arg.front != '-');
		foreach (operNum, ref oper; operands)
		{
			import std.conv : to;
			import std.traits : isDynamicArray, isMutable, isSomeString, isStaticArray;
			alias Oper = Operands[operNum];

			// If an operand has a process method defined, then the handling of arguments is determined by the type of
			// that method's parameter.
			static if (hasMember!(Oper, "proc"))
			{
				alias ProcParamType = Parameters!(oper.proc)[0];
				static if (isDynamicArray!ProcParamType)
				{
					import std.array : array;
					oper.value = oper.proc(operandArgs.array);
					operandArgs = operandArgs.dropExactly(oper.value.length);
				}
				else static if (isStaticArray!ProcParamType)
				{
					import std.array : staticArray;
					string[Parameters!(oper.proc)[0].length] buf;
					size_t i;
					foreach (arg; operandArgs) buf[i++] = arg;
					oper.value = oper.proc(buf);
					operandArgs = operandArgs.dropExactly(i);
				}
				else
				{
					oper.value = oper.proc(operandArgs.front);
					operandArgs = operandArgs.dropOne;
				}
			}
			else
			{
				alias ValType = typeof(oper.value);
				static if (isSomeString!ValType && !isMutable!(ElementEncodingType!ValType))
				{
					static if (is(ValType == string)) oper.value = operandArgs.front;
					else oper.value = operandArgs.front.to!ValType;
					operandArgs = operandArgs.dropOne;
				}
				else static if ((isDynamicArray!ValType && isMutable!(ElementType!ValType)))
				{
					oper.value.length = operandArgs.walkLength;
					size_t i;
					foreach (arg; operandArgs)
					{
						oper.value[i++] = arg.to!(ElementType!ValType);
					}
					operandArgs = operandArgs.dropExactly(oper.value.length);
				}
				else static if (isStaticArray!ValType && isMutable!(ElementType!ValType))
				{
					size_t i;
					foreach (arg; operandArgs)
					{
						if (i < oper.value.length) oper.value[i++] = arg.to!(ElementType!ValType);
					}
					operandArgs = operandArgs.dropExactly(oper.value.length);
				}
				else
				{
					oper.value = operandArgs.front.to!ValType;
					operandArgs = operandArgs.dropOne;
				}
			}
		}
	}

	static struct ParseArgsResult
	{
		/// Writes the program's usage text to stdout.
		void writeUsage()
		{
			import std.stdio : writeln;
			generateUsageText!CommandLineParameters(_programName).writeln;
		}

		/// Writes the program's help text to stdout.
		void writeHelp()
		{
			writeUsage;
			generateAndWriteHelp!CommandLineParameters;
		}

		_Operands operands;
		_Options options;
	private:
		// It would be nice to avoid initializing the fields in `_Operands` and `_Options` when defining them, since
		// they'll be assigned a value later and before use, but to handle symbols unknown to this scope, type
		// inference, to my knowledge, is necessary.

		static struct _Operands
		{
			static foreach (Oper; Operands) mixin("auto ", Oper.id, q{ = Oper.value.init;});
		}
		static struct _Options
		{
			static foreach (Opt; Options) mixin("auto ", Opt.id, q{ = Opt.value.init;});
		}
		string _programName;
	}

	ParseArgsResult result;
	static foreach (i, Oper; Operands) __traits(getMember, result.operands, Oper.id) = operands[i].value;
	static foreach (i, Opt; Options) __traits(getMember, result.options, Opt.id) = options[i].value;
	result._programName = args[0].baseName;
	return result;
}

/**
	Returns an alias sequence that begins with the first element of `TList` that satisfies `pred` and whose remaining
	elements are `TList` sans the "moved" element. If no such element exists, then `def` will occupy the first slot in
	returned alias sequence and the subsequent elements are `TList`.
*/
private template BringToFront(alias pred, alias def, TList...)
{
	import std.meta : AliasSeq, Erase, Filter;
	alias Result = Filter!(pred, TList);
	static if (Result.length == 0) alias BringToFront = AliasSeq!(def, TList);
	else alias BringToFront = AliasSeq!(Result[0], Erase!(Result[0], TList));
}

unittest
{
	import std.meta : AliasSeq;
	import std.traits : isIntegral;
	static assert(is(BringToFront!(isIntegral, int, char, string, long) == AliasSeq!(long, char, string)));
	static assert(is(BringToFront!(isIntegral, int, char, string, float) == AliasSeq!(int, char, string, float)));
}

/// Generates the usage text, e.g. "Usage: ...".
pure
private string generateUsageText(CommandLineParameters...)(string programName)
{
	import std.format : format;
	import std.meta : ApplyLeft, Filter;

	alias Operands = Filter!(ApplyLeft!(isInstanceOf, Operand), CommandLineParameters);
	auto usage = format!"Usage: %s"(programName);
	static foreach (Oper; Operands) usage ~= format!" <%s>"(Oper.name);
	usage ~= " [options]";
	return usage;
}

/// Generates and writes the help text to stdout.
private void generateAndWriteHelp(CommandLineParameters...)()
{
	import std.meta : ApplyLeft, Filter, staticSort;
	import std.stdio : write, writef, writefln, writeln;
	import std.traits : hasStaticMember;

	alias Operands = Filter!(ApplyLeft!(isInstanceOf, Operand), CommandLineParameters);
	enum sortOptionsByLongName(Opt1, Opt2) = Opt1.longName < Opt2.longName;
	alias Options = staticSort!(sortOptionsByLongName, Filter!(ApplyLeft!(isInstanceOf, Option), CommandLineParameters));

	immutable tab = "    ";

	writeln("Options:");

	static foreach (Opt; Options)
	{
		write(tab);
		static if (Opt.shortName.length > 0) writef!"-%s, "(Opt.shortName);
		writef!"--%s"(Opt.longName);
		static if (hasStaticMember!(Opt, "desc")) writef!"%s%s (default: %s)"(tab, Opt.desc, Opt.defVal);
		writeln;
	}
}

/// The class from which all exceptions thrown from `parseArgs` are derived.
class ParseArgsException : Exception
{
	/// Constructor
	nothrow pure @nogc
	this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable nextInChain = null)
	{
		super(msg, file, line, nextInChain);
	}
}

/**
	Thrown when a command-line parameter takes on a command-line argument's value that is invalid by the parameter's
	specification.
*/
class InvalidArgumentException : ParseArgsException
{
	/// Constructor
	nothrow pure @nogc
	this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable nextInChain = null)
	{
		super(msg, file, line, nextInChain);
	}
}
