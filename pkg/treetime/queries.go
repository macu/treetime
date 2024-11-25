package treetime

type NodeSearchParams struct {
	LimitToClass string
	ExcludeClass string
}

type TagQueryParams struct {
	LangTagIDs    []uint
	PreferTagIDs  []uint // prefer results with these tags, in order
	OrderByTagIDs []uint // order results by these tags, combined
	ExcludeTagIDs []uint // exclude results with these tags
}
