local select = select

if ( not Mixin ) then
	function Mixin(object, ...)
		for i = 1, select("#", ...) do
			local mixin = select(i, ...)
			if ( mixin ) then
				for k, v in pairs(mixin) do
					object[k] = v
				end
			end
		end
		return object
	end
end

function CreateFromMixins(...)
	return Mixin({}, ...)
end

function CreateAndInitFromMixin(mixin, ...)
	local object = CreateFromMixins(mixin)
	object:Init(...)
	return object
end

-- Retail's GenerateClosure: binds leading arguments, call-time arguments follow them.
if ( not GenerateClosure ) then
	local unpack = unpack

	function GenerateClosure(f, ...)
		local bound = select("#", ...)
		if ( bound == 0 ) then
			return f
		end

		local args = { ... }
		return function(...)
			local all = { unpack(args, 1, bound) }
			for i = 1, select("#", ...) do
				all[bound + i] = (select(i, ...))
			end
			return f(unpack(all, 1, bound + select("#", ...)))
		end
	end
end